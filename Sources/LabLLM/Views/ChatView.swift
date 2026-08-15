import SwiftUI

struct ChatView: View {
    @EnvironmentObject var trainer: Trainer

    @State private var system = "You are a helpful assistant. Answer clearly and concisely."
    @State private var messages: [ChatMessage] = []
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !trainer.hasModel {
                ContentUnavailableView("No model to chat with yet", systemImage: "bubble.left.and.bubble.right",
                    description: Text("Pretrain a model, then fine-tune it (Training → Fine-tune) so it learns the chat format. Everything stays local."))
                    .frame(maxHeight: .infinity)
            } else {
                transcript
                Divider()
                composer
            }
        }
    }

    private var header: some View {
        HStack {
            WorkbenchPageHeader(eyebrow: "Playground", title: "Chat", subtitle: "A local conversation with the model currently in memory.", icon: "bubble.left.and.bubble.right")
            Spacer()
            Button { messages.removeAll() } label: { Image(systemName: "square.and.pencil") }
                .help("New chat")
                .disabled(messages.isEmpty)
        }
        .padding(20)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    systemBubble
                    ForEach(messages) { m in bubble(role: m.role, text: m.content) }
                    if trainer.isChatting {
                        bubble(role: .assistant, text: trainer.chatStreaming.isEmpty ? "…" : trainer.chatStreaming)
                            .id("streaming")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: trainer.chatStreaming) { _ in withAnimation { proxy.scrollTo("streaming", anchor: .bottom) } }
        }
    }

    private var systemBubble: some View {
        HStack {
            Image(systemName: "gearshape").foregroundStyle(.secondary)
            TextField("System prompt", text: $system, axis: .vertical)
                .textFieldStyle(.plain).font(.callout).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(WorkbenchTheme.panel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
    }

    private func bubble(role: ChatMessage.Role, text: String) -> some View {
        HStack {
            if role == .assistant {
                content(text, color: Color.gray.opacity(0.12), leading: true)
                Spacer(minLength: 60)
            } else {
                Spacer(minLength: 60)
                content(text, color: Color.accentColor.opacity(0.18), leading: false)
            }
        }
    }

    private func content(_ text: String, color: Color, leading: Bool) -> some View {
        Text(text.isEmpty ? " " : text)
            .textSelection(.enabled)
            .padding(10)
            .background(color, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
            .frame(maxWidth: 520, alignment: leading ? .leading : .trailing)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message your model…", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
                .disabled(trainer.isChatting)
            Button(action: send) {
                Image(systemName: "paperplane.fill")
            }
            .buttonStyle(WorkbenchPrimaryButtonStyle())
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || trainer.isChatting)
        }
        .padding()
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !trainer.isChatting else { return }
        messages.append(ChatMessage(role: .user, content: text))
        input = ""
        let history = messages
        trainer.chat(system: system, history: history,
                     params: SamplingParams(maxTokens: 200, temperature: 0.8, topK: 40)) { full in
            messages.append(ChatMessage(role: .assistant, content: full))
        }
    }
}
