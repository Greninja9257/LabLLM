import SwiftUI

struct ServerView: View {
    @EnvironmentObject var server: ModelServer
    @EnvironmentObject var trainer: Trainer
    @State private var portText = "8080"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkbenchPageHeader(eyebrow: "System", title: "Local Model Server", subtitle: "Expose the loaded model through an OpenAI-shaped endpoint for tools running on this Mac.", icon: "server.rack")

                if !trainer.hasModel {
                    Label("No model loaded — train or load a checkpoint first.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                GroupBox("Status") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle().fill(server.isRunning ? .green : .secondary).frame(width: 8, height: 8)
                            Text(server.isRunning ? "Running on http://127.0.0.1:\(server.port)" : "Stopped")
                            Spacer()
                            TextField("Port", text: $portText).textFieldStyle(.roundedBorder).frame(width: 80)
                                .disabled(server.isRunning)
                            if server.isRunning {
                                Button("Stop") { server.stop() }.buttonStyle(WorkbenchSecondaryButtonStyle())
                            } else {
                                Button("Start") {
                                    let port = UInt16(portText) ?? 8080
                                    server.start(trainer: trainer, port: port)
                                }.buttonStyle(WorkbenchPrimaryButtonStyle()).disabled(!trainer.hasModel)
                            }
                        }
                        if let err = server.lastError {
                            Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                        }
                    }.padding(8)
                }

                GroupBox("Try it") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("curl example").font(.caption).foregroundStyle(.secondary)
                        Text("""
                        curl http://127.0.0.1:\(server.port)/v1/chat/completions \\
                          -H "Content-Type: application/json" \\
                          -d '{"messages":[{"role":"user","content":"Hello"}],"stream":true}'
                        """)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(10)
                        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius))
                    }.padding(8)
                }

                GroupBox("Notes") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Endpoints: GET /v1/models, POST /v1/chat/completions").font(.caption)
                        Text("• Add stream: true to receive OpenAI-shaped Server-Sent Events.").font(.caption)
                        Text("• Requests are refused while a training run is active.").font(.caption)
                    }.foregroundStyle(.secondary).padding(8)
                }

                if !server.requestLog.isEmpty {
                    GroupBox("Recent requests") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(server.requestLog, id: \.self) { Text($0).font(.caption.monospaced()) }
                        }.padding(8)
                    }
                }
            }.padding(WorkbenchTheme.pagePadding)
        }
    }
}
