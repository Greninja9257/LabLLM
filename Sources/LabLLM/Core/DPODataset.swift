import Foundation
import MLX

struct PreferenceExample {
    var context: [ChatMessage]   // system/user turns leading up to the response
    var chosen: String           // preferred assistant reply
    var rejected: String         // dispreferred assistant reply
}

/// Pairwise preference dataset for DPO. Each batch yields matched (chosen, rejected)
/// sequences with assistant-only loss masks, same masking idea as SFT.
final class DPODataset {
    let tokenizer: Tokenizer
    let blockSize: Int
    private let examples: [PreferenceExample]

    init(examples: [PreferenceExample], tokenizer: Tokenizer, blockSize: Int) {
        self.examples = examples.isEmpty ? DPODataset.builtin : examples
        self.tokenizer = tokenizer
        self.blockSize = blockSize
    }

    /// Returns chosen (x,y,w) and rejected (x,y,w), each (B, L) / (B, L) / (B, L).
    func batch(batchSize: Int) -> (chosen: (MLXArray, MLXArray, MLXArray), rejected: (MLXArray, MLXArray, MLXArray)) {
        var picks: [PreferenceExample] = []
        for _ in 0 ..< batchSize { picks.append(examples.randomElement() ?? DPODataset.builtin[0]) }

        func encode(_ text: String, from ex: PreferenceExample) -> (ids: [Int32], mask: [Float]) {
            var conv = ex.context
            conv.append(ChatMessage(role: .assistant, content: text))
            return ChatTemplate.encodeConversation(conv, tok: tokenizer)
        }

        func pack(_ picks: [PreferenceExample], field: (PreferenceExample) -> String) -> (MLXArray, MLXArray, MLXArray) {
            let L = blockSize
            var xs = [Int32](); var ys = [Int32](); var ws = [Float]()
            for ex in picks {
                var (ids, mask) = encode(field(ex), from: ex)
                if ids.count > L + 1 { ids = Array(ids.prefix(L + 1)); mask = Array(mask.prefix(L + 1)) }
                while ids.count < L + 1 { ids.append(tokenizer.padID); mask.append(0) }
                for i in 0 ..< L { xs.append(ids[i]); ys.append(ids[i + 1]); ws.append(mask[i + 1]) }
            }
            return (MLXArray(xs, [picks.count, L]), MLXArray(ys, [picks.count, L]), MLXArray(ws, [picks.count, L]))
        }

        return (pack(picks) { $0.chosen }, pack(picks) { $0.rejected })
    }

    /// A tiny built-in preference set so DPO is runnable out of the box.
    static let builtin: [PreferenceExample] = [
        .init(context: [.init(role: .user, content: "How do I get better at cooking?")],
              chosen: "Start simple: pick a few recipes you enjoy eating, cook them repeatedly, and pay attention to timing and seasoning each time.",
              rejected: "idk just cook more lol"),
        .init(context: [.init(role: .user, content: "Explain gravity simply.")],
              chosen: "Gravity is the pull that draws objects with mass toward each other — it's why things fall and why planets orbit stars.",
              rejected: "gravity is a thing that pulls stuff down because of physics reasons"),
        .init(context: [.init(role: .user, content: "Can you help me plan my day?")],
              chosen: "Sure — tell me your top priorities today and roughly how much time you have, and I'll help you sequence them.",
              rejected: "sure whatever you want"),
        .init(context: [.init(role: .user, content: "What's a good icebreaker question?")],
              chosen: "\"What's something you've learned recently that changed how you think?\" tends to spark genuine conversation.",
              rejected: "uh i dont know, ask them their name maybe"),
    ]
}
