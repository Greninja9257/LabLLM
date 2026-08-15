import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case system, user, assistant }
    let id = UUID()
    var role: Role
    var content: String
}

/// Formats conversations into the token stream the model trains/generates on:
///   <|system|> … <|end|> <|user|> … <|end|> <|assistant|> … <|end|>
/// For SFT, only the assistant's content + its closing <|end|> are learning
/// targets (mask = 1); everything else is context (mask = 0). This is the
/// "assistant turns are the learning targets" idea.
enum ChatTemplate {
    private static func marker(_ role: ChatMessage.Role) -> Special {
        switch role { case .system: return .system; case .user: return .user; case .assistant: return .assistant }
    }

    /// Training encoding: returns token ids and a per-token loss mask of equal length.
    static func encodeConversation(_ msgs: [ChatMessage], tok: Tokenizer) -> (ids: [Int32], mask: [Float]) {
        var ids: [Int32] = []
        var mask: [Float] = []

        func push(_ id: Int32, learn: Bool) { ids.append(id); mask.append(learn ? 1 : 0) }

        for m in msgs {
            push(tok.id(marker(m.role)), learn: false)          // role marker = context
            let content = tok.encode(m.content)
            let learn = (m.role == .assistant)
            for t in content { push(t, learn: learn) }
            push(tok.id(.end), learn: learn)                     // learn to stop, on assistant turns
        }
        return (ids, mask)
    }

    /// Generation prompt: full history followed by a bare <|assistant|> marker so
    /// the model continues by producing the assistant's reply.
    static func encodePrompt(system: String, history: [ChatMessage], tok: Tokenizer) -> [Int32] {
        var msgs: [ChatMessage] = []
        if !system.isEmpty { msgs.append(ChatMessage(role: .system, content: system)) }
        msgs.append(contentsOf: history)

        var ids: [Int32] = []
        for m in msgs {
            ids.append(tok.id(marker(m.role)))
            ids.append(contentsOf: tok.encode(m.content))
            ids.append(tok.id(.end))
        }
        ids.append(tok.id(.assistant))   // model continues from here
        return ids
    }
}
