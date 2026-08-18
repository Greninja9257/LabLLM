import Foundation
import SQLite3

enum ConversationImportError: LocalizedError {
    case noValidRows
    case network(String)
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .noValidRows: return "No rows in this file matched a recognized conversation format."
        case .network(let r): return "Network error: \(r)"
        case .badStatus(let code): return "Server returned status \(code). Check the repo/file path."
        }
    }
}

/// Parses JSONL conversation data into [ChatMessage] groups. Tolerates a couple of
/// common schemas so real-world files (including ones straight off Hugging Face)
/// have a reasonable chance of working without preprocessing:
///   1. {"messages": [{"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}]}
///   2. {"instruction": "...", "input": "...", "output": "..."}  (Alpaca-style)
///   3. {"prompt": "...", "response": "..."}
/// Malformed lines are skipped rather than failing the whole import.
enum ConversationImport {
    static func pairCount(in conversation: [ChatMessage]) -> Int {
        conversation.filter { $0.role == .assistant && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    static func parseJSONL(_ text: String) -> [[ChatMessage]] {
        var results: [[ChatMessage]] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let conversation = conversation(from: obj) { results.append(conversation) }
        }
        return results
    }

    static func parseJSON(_ text: String) -> [[ChatMessage]] {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let rows = json as? [[String: Any]] { return rows.compactMap(conversation(from:)) }
        if let row = json as? [String: Any] { return conversation(from: row).map { [$0] } ?? [] }
        return []
    }

    static func conversation(from obj: [String: Any]) -> [ChatMessage]? {
        if let msgs = obj["messages"] as? [[String: Any]] {
            let conv = msgs.compactMap { message -> ChatMessage? in
                guard let roleStr = message["role"] as? String,
                      let content = message["content"] as? String else { return nil }
                let role: ChatMessage.Role
                switch roleStr.lowercased() {
                case "user", "human": role = .user
                case "assistant", "gpt", "bot": role = .assistant
                case "system": role = .system
                default: return nil
                }
                return ChatMessage(role: role, content: content)
            }
            return conv.contains(where: { $0.role == .assistant }) ? conv : nil
        }
        if let instruction = obj["instruction"] as? String,
           let output = (obj["output"] ?? obj["response"] ?? obj["completion"]) as? String {
            let input = (obj["input"] ?? obj["context"]) as? String
            let userText = (input?.isEmpty == false) ? "\(instruction)\n\n\(input!)" : instruction
            return [ChatMessage(role: .user, content: userText), ChatMessage(role: .assistant, content: output)]
        }
        if let prompt = obj["prompt"] as? String,
           let response = (obj["response"] ?? obj["completion"]) as? String {
            return [ChatMessage(role: .user, content: prompt), ChatMessage(role: .assistant, content: response)]
        }
        if let source = obj["src"] as? String, let target = obj["tgt"] as? String {
            return [ChatMessage(role: .user, content: source), ChatMessage(role: .assistant, content: target)]
        }
        if let question = obj["question"] as? String {
            if let answer = obj["answer"] as? String {
                return [ChatMessage(role: .user, content: question), ChatMessage(role: .assistant, content: answer)]
            }
            if let answers = obj["answers"] as? [String: Any], let texts = answers["text"] as? [String], let answer = texts.first {
                return [ChatMessage(role: .user, content: question), ChatMessage(role: .assistant, content: answer)]
            }
        }
        return nil
    }

    static func conversation(from row: [String: HFJSONValue]) -> [ChatMessage]? {
        conversation(from: row.mapValues(\.foundationValue))
    }

    static func conversations(from rows: [[String: HFJSONValue]]) -> [[ChatMessage]] {
        let direct = rows.compactMap(conversation(from:))
        guard direct.isEmpty else { return direct }

        // OpenAssistant stores one message per row. Rebuild each assistant leaf by
        // walking its parent chain, retaining only complete user/assistant paths.
        let raw = rows.map { $0.mapValues(\.foundationValue) }
        let byID = Dictionary(uniqueKeysWithValues: raw.compactMap { row -> (String, [String: Any])? in
            guard let id = row["message_id"] as? String else { return nil }
            return (id, row)
        })
        return raw.compactMap { row in
            guard let role = row["role"] as? String, role.lowercased() == "assistant" else { return nil }
            var path: [[String: Any]] = []
            var current: [String: Any]? = row
            var visited = Set<String>()
            while let message = current, let id = message["message_id"] as? String, !visited.contains(id) {
                visited.insert(id)
                path.append(message)
                current = (message["parent_id"] as? String).flatMap { byID[$0] }
            }
            let messages = path.reversed().compactMap { message -> ChatMessage? in
                guard let text = message["text"] as? String, !text.isEmpty,
                      let role = message["role"] as? String else { return nil }
                switch role.lowercased() {
                case "prompter", "user": return ChatMessage(role: .user, content: text)
                case "assistant": return ChatMessage(role: .assistant, content: text)
                default: return nil
                }
            }
            return messages.contains(where: { $0.role == .assistant }) && messages.count >= 2 ? messages : nil
        }
    }

    static func pretrainingText(from row: [String: HFJSONValue]) -> String? {
        let preferredKeys = ["text", "content", "document", "body", "article", "completion", "output", "abstract", "poem", "poem_text", "story"]
        let lookup = Dictionary(uniqueKeysWithValues: row.map { ($0.key.lowercased(), $0.value) })
        let preferred = preferredKeys.compactMap { lookup[$0]?.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !preferred.isEmpty { return preferred.joined(separator: "\n\n") }
        let strings = row.values.compactMap(collectText).filter { !$0.isEmpty }
        return strings.isEmpty ? nil : strings.joined(separator: "\n")
    }

    private static func collectText(_ value: HFJSONValue) -> String? {
        switch value {
        case .string(let text): return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .array(let values):
            let text = values.compactMap(collectText).filter { !$0.isEmpty }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        case .object(let values):
            let text = values.values.compactMap(collectText).filter { !$0.isEmpty }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        default: return nil
        }
    }

    static func parseIMessageDatabase(at url: URL) throws -> [[ChatMessage]] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            throw ConversationImportError.network("Couldn't open chat.db. In System Settings, grant LabLLM Full Disk Access, then choose ~/Library/Messages/chat.db.")
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT chat.chat_identifier, message.is_from_me, message.text
        FROM message
        JOIN chat_message_join ON chat_message_join.message_id = message.ROWID
        JOIN chat ON chat.ROWID = chat_message_join.chat_id
        WHERE message.text IS NOT NULL AND length(trim(message.text)) > 0
        ORDER BY chat.chat_identifier, message.date
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ConversationImportError.network("Couldn't read messages from this chat database.")
        }
        defer { sqlite3_finalize(statement) }

        var chats: [String: [ChatMessage]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let identifier = sqlite3_column_text(statement, 0),
                  let body = sqlite3_column_text(statement, 2) else { continue }
            let chatID = String(cString: identifier)
            let text = String(cString: body).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let role: ChatMessage.Role = sqlite3_column_int(statement, 1) == 1 ? .assistant : .user
            chats[chatID, default: []].append(ChatMessage(role: role, content: text))
        }
        return chats.values.filter { $0.count >= 2 && $0.contains(where: { $0.role == .assistant }) }
    }

    static func parsePreferenceJSONL(_ text: String) -> [PreferenceExample] {
        var results: [PreferenceExample] = []
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard let prompt = obj["prompt"] as? String,
                  let chosen = obj["chosen"] as? String,
                  let rejected = obj["rejected"] as? String else { continue }
            results.append(PreferenceExample(context: [ChatMessage(role: .user, content: prompt)],
                                             chosen: chosen, rejected: rejected))
        }
        return results
    }
}

enum DatasetLimitMode: String, Codable, CaseIterable, Identifiable {
    case percent = "% of rows"
    case lines = "Lines"
    var id: String { rawValue }
}

/// Downloads a file from a Hugging Face dataset repo via the public `resolve/main`
/// raw-file endpoint (works for public repos without auth). Errors are surfaced,
/// never silently swallowed, since a 404 here almost always means the file path
/// needs adjusting for that specific repo's layout.
enum HFDownloader {
    static func url(repo: String, filePath: String) -> URL? {
        URL(string: "https://huggingface.co/datasets/\(repo)/resolve/main/\(filePath)")
    }

    static func download(repo: String, filePath: String, progress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }) async throws -> String {
        guard let url = url(repo: repo, filePath: filePath) else {
            throw ConversationImportError.network("Invalid repo or file path.")
        }
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(from: url)
        } catch {
            throw ConversationImportError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ConversationImportError.badStatus(http.statusCode)
        }
        let expected = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        var data = Data()
        if let expected { data.reserveCapacity(Int(min(expected, Int64(Int.max)))) }
        var downloaded: Int64 = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            downloaded += 1
            if downloaded % 131_072 == 0 { progress(downloaded, expected) }
        }
        progress(downloaded, expected ?? downloaded)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConversationImportError.network("Downloaded file wasn't valid UTF-8 text (it may be a Parquet/Arrow file rather than raw JSONL — try a different file path).")
        }
        return text
    }

    /// Cache downloaded datasets locally so re-opening the app doesn't re-fetch.
    static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LabLLM/DatasetCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
