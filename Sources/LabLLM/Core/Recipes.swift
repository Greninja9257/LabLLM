import Foundation

/// A recipe bundles a model config + training hyperparameters + a suggested
/// tokenizer, so one click sets up a sensible run.
struct Recipe: Identifiable {
    let id = UUID()
    let name: String
    let summary: String
    let icon: String
    let gpt: GPTConfig
    let train: TrainConfig
    let tokenizer: TokenizerKind

    static let all: [Recipe] = [
        Recipe(name: "Tiny GPT",
               summary: "Smallest useful model. Trains in seconds on any M-series chip. Great first run.",
               icon: "hare",
               gpt: GPTConfig(blockSize: 64, nEmbd: 128, nLayers: 4, nHeads: 4),
               train: TrainConfig(batchSize: 32, maxSteps: 500, learningRate: 3e-3, warmupSteps: 50),
               tokenizer: .character),
        Recipe(name: "Shakespeare",
               summary: "Classic char-level model. Import a Shakespeare .txt for best results.",
               icon: "theatermasks",
               gpt: GPTConfig(blockSize: 128, nEmbd: 256, nLayers: 6, nHeads: 8),
               train: TrainConfig(batchSize: 32, maxSteps: 3000, learningRate: 1e-3, warmupSteps: 100),
               tokenizer: .character),
        Recipe(name: "Story model",
               summary: "Slightly larger context for short-story style text.",
               icon: "book",
               gpt: GPTConfig(blockSize: 256, nEmbd: 384, nLayers: 6, nHeads: 6),
               train: TrainConfig(batchSize: 24, maxSteps: 4000, learningRate: 6e-4, warmupSteps: 200),
               tokenizer: .byte),
        Recipe(name: "Overfit demo",
               summary: "Tiny data + big model on purpose — watch train loss crater while val loss climbs.",
               icon: "exclamationmark.triangle",
               gpt: GPTConfig(blockSize: 128, nEmbd: 512, nLayers: 8, nHeads: 8),
               train: TrainConfig(batchSize: 8, maxSteps: 2000, learningRate: 1e-3, warmupSteps: 20),
               tokenizer: .character),
    ]
}
