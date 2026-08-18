import Foundation

/// The data a recipe needs, expressed as a Hugging Face repository so the recipe
/// can install it itself instead of telling the user to go find it.
struct RecipeDataset {
    let repo: String
    let title: String
    let kind: InstalledDataset.Kind
    /// Preferred file inside the repo. When nil (or absent upstream) the recipe
    /// falls back to the Dataset Viewer.
    let fileContains: String?
    /// Rows to pull when importing through the viewer.
    let rowLimit: Int
    let approximateSize: String
}

/// A recipe is a complete, runnable plan: architecture, hyperparameters, tokenizer,
/// the dataset to train on, and which run mode to start in. Applying one leaves the
/// Training page ready to press Start — it is not just a pair of config structs.
struct Recipe: Identifiable {
    let id: String
    let name: String
    let summary: String
    /// The concrete thing to watch while it runs. A recipe that teaches nothing is
    /// just a preset.
    let watchFor: String
    let icon: String
    let mode: RunMode
    let gpt: GPTConfig
    let train: TrainConfig
    let tokenizer: TokenizerKind
    let data: RecipeDataset
    /// Rough wall-clock range on Apple Silicon, stated as a range because it
    /// depends on the chip and what else is running.
    let minutes: ClosedRange<Int>
    /// Set when the recipe only makes sense on top of an existing trained model.
    let needsTrainedModel: Bool

    var shapeTag: String { "\(gpt.nLayers)L · \(gpt.nEmbd)d" }
    var contextTag: String { "ctx \(gpt.blockSize)" }
    var stepsTag: String { "\(train.maxSteps.formatted()) steps" }
    var timeTag: String { "≈\(minutes.lowerBound)–\(minutes.upperBound) min" }

    static let all: [Recipe] = [
        Recipe(id: "first-run",
               name: "First run: Tiny Shakespeare",
               summary: "The smallest end-to-end run in the app: a 4-layer character model on 1 MB of Shakespeare.",
               watchFor: "Loss drops from ~4.2 (random guessing over the vocabulary) to under 2.0, and the samples turn from noise into word-shaped text.",
               icon: "hare",
               mode: .pretrain,
               gpt: GPTConfig(blockSize: 64, nEmbd: 128, nLayers: 4, nHeads: 4),
               train: TrainConfig(batchSize: 32, maxSteps: 500, learningRate: 3e-3, warmupSteps: 50,
                                  evalEvery: 50, sampleEvery: 100, checkpointEvery: 250),
               tokenizer: .character,
               data: RecipeDataset(repo: "karpathy/tiny_shakespeare", title: "Tiny Shakespeare",
                                   kind: .corpus, fileContains: "input.txt", rowLimit: 40_000,
                                   approximateSize: "1.1 MB"),
               minutes: 1...4,
               needsTrainedModel: false),

        Recipe(id: "tinystories",
               name: "TinyStories: real sentences",
               summary: "A 6-layer model on simple children's stories — the smallest setup that produces genuinely coherent sentences.",
               watchFor: "Validation loss keeps falling with training loss. Samples gain grammar, then plot. If val loss flattens while train loss falls, the model has started memorizing.",
               icon: "book",
               mode: .pretrain,
               gpt: GPTConfig(blockSize: 256, nEmbd: 384, nLayers: 6, nHeads: 6),
               train: TrainConfig(batchSize: 24, maxSteps: 3_000, learningRate: 6e-4, warmupSteps: 200,
                                  evalEvery: 100, sampleEvery: 250, checkpointEvery: 500),
               tokenizer: .byte,
               data: RecipeDataset(repo: "roneneldan/TinyStories", title: "TinyStories",
                                   kind: .corpus, fileContains: nil, rowLimit: 20_000,
                                   approximateSize: "~25 MB of rows"),
               minutes: 15...45,
               needsTrainedModel: false),

        Recipe(id: "chat-lora",
               name: "Teach it to chat (LoRA)",
               summary: "LoRA fine-tune on short everyday conversations, so a pretrained model starts answering instead of continuing text.",
               watchFor: "Only the assistant turns count toward the loss. After a few hundred steps the model stops rambling and starts replying in turns — check it in Chat.",
               icon: "bubble.left.and.bubble.right",
               mode: .sft,
               gpt: GPTConfig(blockSize: 256, nEmbd: 384, nLayers: 6, nHeads: 6),
               train: TrainConfig(batchSize: 8, maxSteps: 800, learningRate: 2e-4, warmupSteps: 40,
                                  checkpointEvery: 200, loraRank: 8, loraAlpha: 16),
               tokenizer: .byte,
               data: RecipeDataset(repo: "HuggingFaceTB/everyday-conversations-llama3.1-2k",
                                   title: "Everyday Conversations 2k",
                                   kind: .fineTune, fileContains: nil, rowLimit: 2_260,
                                   approximateSize: "2,260 rows"),
               minutes: 5...20,
               needsTrainedModel: true),

        Recipe(id: "instructions",
               name: "Instruction following",
               summary: "Full fine-tune on Dolly-style instruction/response pairs for models that answer tasks rather than chat.",
               watchFor: "Responses become instruction-shaped: they answer the asked question and stop, instead of inventing a new question.",
               icon: "list.bullet.rectangle",
               mode: .sft,
               gpt: GPTConfig(blockSize: 256, nEmbd: 384, nLayers: 6, nHeads: 6),
               train: TrainConfig(batchSize: 8, maxSteps: 1_500, learningRate: 1e-4, warmupSteps: 100,
                                  checkpointEvery: 300),
               tokenizer: .byte,
               data: RecipeDataset(repo: "databricks/databricks-dolly-15k", title: "Dolly 15k",
                                   kind: .fineTune, fileContains: "databricks-dolly-15k.jsonl",
                                   rowLimit: 5_000, approximateSize: "13 MB"),
               minutes: 10...35,
               needsTrainedModel: true),

        Recipe(id: "overfit-lab",
               name: "Overfitting lab",
               summary: "A deliberately oversized model on a deliberately tiny slice of text — the fastest way to see overfitting for yourself.",
               watchFor: "Training loss keeps diving while validation loss bottoms out and climbs. That gap is overfitting, and it is the reason validation exists.",
               icon: "exclamationmark.triangle",
               mode: .pretrain,
               gpt: GPTConfig(blockSize: 128, nEmbd: 512, nLayers: 8, nHeads: 8),
               train: TrainConfig(batchSize: 8, maxSteps: 1_500, learningRate: 1e-3, warmupSteps: 20,
                                  evalEvery: 25, sampleEvery: 250, checkpointEvery: 500),
               tokenizer: .character,
               data: RecipeDataset(repo: "karpathy/tiny_shakespeare", title: "Tiny Shakespeare",
                                   kind: .corpus, fileContains: "input.txt", rowLimit: 40_000,
                                   approximateSize: "1.1 MB (5% used)"),
               minutes: 5...15,
               needsTrainedModel: false),
    ]

    /// The overfitting lab intentionally trains on a sliver of the corpus.
    var corpusPercent: Double { id == "overfit-lab" ? 5 : 100 }
}
