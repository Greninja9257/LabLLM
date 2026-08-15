import Foundation
import MLX

/// Supervised fine-tuning dataset. Holds conversations and yields masked target
/// batches: context targets are encoded as padID, assistant targets keep their
/// real token IDs. Sequences are padded/truncated to the model's context length.
final class SFTDataset {
    let tokenizer: Tokenizer
    let blockSize: Int
    let padID: Int32
    private let trainingConversations: [[ChatMessage]]
    private let validationConversations: [[ChatMessage]]

    var count: Int { trainingConversations.count }
    var hasValidationSplit: Bool { validationConversations.count > 0 }

    init(conversations: [[ChatMessage]], tokenizer: Tokenizer, blockSize: Int) {
        precondition(!conversations.isEmpty, "SFTDataset requires imported conversations.")
        let source = conversations.filter { conv in
            ChatTemplate.encodeConversation(conv, tok: tokenizer).mask.contains { $0 > 0 }
        }
        precondition(!source.isEmpty, "SFTDataset requires at least one assistant response.")
        // Keep a stable held-out tail so the orange validation curve reveals
        // overfitting instead of reporting the same rows used for optimization.
        let validationCount = source.count >= 2 ? max(1, source.count / 10) : 0
        self.trainingConversations = validationCount > 0 ? Array(source.dropLast(validationCount)) : source
        self.validationConversations = validationCount > 0 ? Array(source.suffix(validationCount)) : []
        self.tokenizer = tokenizer
        self.blockSize = blockSize
        self.padID = tokenizer.padID
    }

    /// Returns (x, y): x,y are Int32 (B, L). Non-learning targets are encoded as
    /// padID so the loss can derive its mask while using MLX's stable two-array
    /// value-and-grad wrapper.
    func batch(batchSize: Int, validation: Bool = false) -> (MLXArray, MLXArray) {
        let L = blockSize
        let B = max(batchSize, 1)
        var xs = [Int32](); var ys = [Int32]()
        xs.reserveCapacity(B * L); ys.reserveCapacity(B * L)

        for _ in 0 ..< B {
            let source = validation && !validationConversations.isEmpty ? validationConversations : trainingConversations
            guard let conv = source.randomElement() else { continue }
            var (ids, mask) = ChatTemplate.encodeConversation(conv, tok: tokenizer)

            // Need L+1 tokens to form (x, y). For long conversations, keep a
            // window ending at the latest assistant target so SFT always has
            // something to learn from instead of training on context-only tokens.
            if ids.count > L + 1 {
                let lastLearn = mask.lastIndex { $0 > 0 } ?? (L + 1)
                let end = min(ids.count, max(L + 1, lastLearn + 1))
                let start = max(0, end - (L + 1))
                ids = Array(ids[start ..< end])
                mask = Array(mask[start ..< end])
            }
            while ids.count < L + 1 { ids.append(padID); mask.append(0) }

            for i in 0 ..< L {
                xs.append(ids[i])
                ys.append(mask[i + 1] > 0 ? ids[i + 1] : padID)   // mask aligns with target token
            }
        }

        return (MLXArray(xs, [B, L]), MLXArray(ys, [B, L]))
    }
}
