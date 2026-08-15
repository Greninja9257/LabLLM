import Foundation
import Network

/// A minimal local HTTP server exposing the in-memory model at an OpenAI-shaped
/// endpoint, so other local tools can talk to it. Deliberately small: it parses
/// just enough HTTP/1.1 to read a JSON body and write a JSON response. Chat
/// completions optionally stream OpenAI-shaped SSE chunks when `stream: true`.
///
/// Endpoints:
///   GET  /v1/models            -> lists the loaded model
///   POST /v1/chat/completions  -> { model, messages, temperature?, max_tokens? }
final class ModelServer: ObservableObject {
    @Published var isRunning = false
    @Published var port: UInt16 = 8080
    @Published var lastError: String?
    @Published var requestLog: [String] = []

    private var listener: NWListener?
    private weak var trainer: Trainer?
    private let queue = DispatchQueue(label: "com.labllm.server")

    func start(trainer: Trainer, port: UInt16) {
        stop()
        self.trainer = trainer
        self.port = port
        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed(let err): DispatchQueue.main.async { self?.lastError = err.localizedDescription; self?.isRunning = false }
                case .ready: DispatchQueue.main.async { self?.isRunning = true; self?.lastError = nil }
                case .cancelled: DispatchQueue.main.async { self?.isRunning = false }
                default: break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = "Couldn't start server: \(error.localizedDescription)"
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection: connection, buffer: Data())
    }

    private func readRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buf = buffer
            if let data, !data.isEmpty { buf.append(data) }

            if let headerEnd = Self.range(of: "\r\n\r\n", in: buf) {
                let headerData = buf.subdata(in: 0 ..< headerEnd.lowerBound)
                let headerText = String(data: headerData, encoding: .utf8) ?? ""
                let contentLength = Self.headerValue("Content-Length", in: headerText).flatMap { Int($0) } ?? 0
                let bodyStart = headerEnd.upperBound
                let bodySoFar = buf.count - bodyStart

                if bodySoFar >= contentLength {
                    let body = buf.subdata(in: bodyStart ..< buf.count)
                    self.respond(connection: connection, headerText: headerText, body: body)
                    return
                }
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.readRequest(connection: connection, buffer: buf)
        }
    }

    private func respond(connection: NWConnection, headerText: String, body: Data) {
        let firstLine = headerText.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : ""
        let path = parts.count > 1 ? String(parts[1]) : ""
        DispatchQueue.main.async { self.requestLog.insert("\(method) \(path)", at: 0); if self.requestLog.count > 30 { self.requestLog.removeLast() } }

        var status = "200 OK"
        var json: [String: Any] = [:]

        guard let trainer = trainer else {
            status = "503 Service Unavailable"; json = ["error": "Server has no trainer reference."]
            send(connection: connection, status: status, json: json); return
        }

        if method == "GET" && path == "/v1/models" {
            json = ["object": "list", "data": [["id": trainer.hasModel ? "labllm-local" : "none", "object": "model"]]]
        } else if method == "POST" && path == "/v1/chat/completions" {
            guard trainer.hasModel else {
                status = "503 Service Unavailable"; json = ["error": "No model loaded in LabLLM yet."]
                send(connection: connection, status: status, json: json); return
            }
            guard !trainer.isTraining else {
                status = "503 Service Unavailable"; json = ["error": "A training run is in progress; try again after it finishes."]
                send(connection: connection, status: status, json: json); return
            }
            let request = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            let msgsRaw = request["messages"] as? [[String: Any]] ?? []
            var system = ""
            var history: [ChatMessage] = []
            for m in msgsRaw {
                guard let role = m["role"] as? String, let content = m["content"] as? String else { continue }
                if role == "system" { system = content }
                else if role == "user" { history.append(ChatMessage(role: .user, content: content)) }
                else if role == "assistant" { history.append(ChatMessage(role: .assistant, content: content)) }
            }
            let temperature = Float(request["temperature"] as? Double ?? 0.8)
            let maxTokens = request["max_tokens"] as? Int ?? 200
            let streaming = request["stream"] as? Bool ?? false

            if streaming {
                sendStreaming(connection: connection, trainer: trainer, system: system, history: history,
                              maxTokens: maxTokens, temperature: temperature)
                return
            }

            let reply = trainer.serverComplete(system: system, history: history, maxTokens: maxTokens, temperature: temperature) ?? ""
            json = [
                "id": "labllm-\(UUID().uuidString.prefix(8))",
                "object": "chat.completion",
                "choices": [["index": 0, "message": ["role": "assistant", "content": reply], "finish_reason": "stop"]],
            ]
        } else {
            status = "404 Not Found"; json = ["error": "Unknown endpoint. Try GET /v1/models or POST /v1/chat/completions."]
        }

        send(connection: connection, status: status, json: json)
    }

    private func sendStreaming(connection: NWConnection, trainer: Trainer, system: String, history: [ChatMessage],
                               maxTokens: Int, temperature: Float) {
        let header = Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n".utf8)
        connection.send(content: header, completion: .contentProcessed { [weak self] error in
            guard error == nil else { connection.cancel(); return }
            let id = "labllm-\(UUID().uuidString.prefix(8))"
            let streamed = trainer.serverStream(system: system, history: history, maxTokens: maxTokens, temperature: temperature) { piece in
                let event: [String: Any] = [
                    "id": id,
                    "object": "chat.completion.chunk",
                    "choices": [["index": 0, "delta": ["content": piece], "finish_reason": NSNull()]]
                ]
                self?.sendSSE(connection: connection, json: event)
            }
            if streamed {
                self?.sendSSE(connection: connection, json: ["id": id, "object": "chat.completion.chunk", "choices": [["index": 0, "delta": [:], "finish_reason": "stop"]]])
                connection.send(content: Data("data: [DONE]\n\n".utf8), completion: .contentProcessed { _ in connection.cancel() })
            } else {
                connection.cancel()
            }
        })
    }

    private func sendSSE(connection: NWConnection, json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json), let string = String(data: data, encoding: .utf8) else { return }
        connection.send(content: Data("data: \(string)\n\n".utf8), completion: .contentProcessed { _ in })
    }

    private func send(connection: NWConnection, status: String, json: [String: Any]) {
        let bodyData = (try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])) ?? Data("{}".utf8)
        var response = "HTTP/1.1 \(status)\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Content-Length: \(bodyData.count)\r\n"
        response += "Connection: close\r\n\r\n"
        var full = Data(response.utf8)
        full.append(bodyData)
        connection.send(content: full, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func range(of needle: String, in data: Data) -> Range<Data.Index>? {
        data.range(of: Data(needle.utf8))
    }
    private static func headerValue(_ name: String, in headerText: String) -> String? {
        for line in headerText.components(separatedBy: "\r\n") {
            let pieces = line.split(separator: ":", maxSplits: 1)
            if pieces.count == 2, pieces[0].trimmingCharacters(in: .whitespaces).lowercased() == name.lowercased() {
                return pieces[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
