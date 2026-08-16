import Testing
import MLX
@testable import LabLLM

struct DatasetCorrectnessTests {
    private func ensureMLX() {
        try! MLXMetalLibrary.ensureAvailable()
    }

    @Test func textDatasetIncludesFinalValidWindow() {
        ensureMLX()
        let tok = Tokenizer.character(from: "abcdef")
        let dataset = TextDataset(text: "abcdef", tokenizer: tok, blockSize: 3, valFraction: 0)

        #expect(TextDataset.validWindowCount(tokenCount: 6, blockSize: 3) == 3)
        #expect(dataset.trainingWindowStarts() == [0, 1, 2])

        let (x, y) = dataset.fixedBatch(starts: [2])
        #expect(x.asArray(Int32.self) == tok.encode("cde"))
        #expect(y.asArray(Int32.self) == tok.encode("def"))
    }

    @Test func textDatasetPadsShortCorpusAndMasksTargetsAvailable() {
        ensureMLX()
        let tok = Tokenizer.character(from: "a")
        let dataset = TextDataset(text: "a", tokenizer: tok, blockSize: 4, valFraction: 0)
        let (_, y) = dataset.fixedBatch(starts: [0])

        #expect(y.asArray(Int32.self).count == 4)
        #expect(y.asArray(Int32.self).dropFirst().allSatisfy { $0 == tok.padID })
    }

    @Test func textDatasetSamplingIsSeededAndReproducible() {
        ensureMLX()
        let tok = Tokenizer.character(from: "abcdefghijklmnopqrstuvwxyz")
        let dataset = TextDataset(text: "abcdefghijklmnopqrstuvwxyz", tokenizer: tok, blockSize: 5, valFraction: 0)
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)

        let first = dataset.batch(batchSize: 8, rng: &a)
        let second = dataset.batch(batchSize: 8, rng: &b)

        #expect(first.0.asArray(Int32.self) == second.0.asArray(Int32.self))
        #expect(first.1.asArray(Int32.self) == second.1.asArray(Int32.self))
    }

    @Test func validationBatchesAreFixed() {
        ensureMLX()
        let tok = Tokenizer.character(from: "abcdefghijklmnopqrstuvwxyz")
        let dataset = TextDataset(text: "abcdefghijklmnopqrstuvwxyz", tokenizer: tok, blockSize: 4, valFraction: 0.3)

        let first = dataset.fixedValidationBatches(batchSize: 2, maxBatches: 2)
        let second = dataset.fixedValidationBatches(batchSize: 2, maxBatches: 2)

        #expect(first.count == second.count)
        for (lhs, rhs) in zip(first, second) {
            #expect(lhs.0.asArray(Int32.self) == rhs.0.asArray(Int32.self))
            #expect(lhs.1.asArray(Int32.self) == rhs.1.asArray(Int32.self))
        }
    }

    @Test func sftSamplingIsSeededAndReproducible() {
        ensureMLX()
        let tok = Tokenizer.character(from: "hello world answer one two")
        let conversations = [
            [ChatMessage(role: .user, content: "hello"), ChatMessage(role: .assistant, content: "answer one")],
            [ChatMessage(role: .user, content: "world"), ChatMessage(role: .assistant, content: "answer two")]
        ]
        let dataset = SFTDataset(conversations: conversations, tokenizer: tok, blockSize: 12)
        var a = SeededGenerator(seed: 99)
        var b = SeededGenerator(seed: 99)

        let first = dataset.batch(batchSize: 4, rng: &a)
        let second = dataset.batch(batchSize: 4, rng: &b)

        #expect(first.0.asArray(Int32.self) == second.0.asArray(Int32.self))
        #expect(first.1.asArray(Int32.self) == second.1.asArray(Int32.self))
    }

    @Test func dpoTruncationKeepsChosenAndRejectedAssistantTargets() {
        let text = "prompt context chosen rejected " + String(repeating: "x ", count: 80)
        let tok = Tokenizer.character(from: text)
        let longContext = String(repeating: "x ", count: 80)
        let example = PreferenceExample(
            context: [.init(role: .user, content: longContext)],
            chosen: "chosen",
            rejected: "rejected"
        )
        let dataset = DPODataset(examples: [example], tokenizer: tok, blockSize: 16)
        let encoded = dataset.encodedPairForTesting(example)

        #expect(encoded.chosen.mask.contains { $0 > 0 })
        #expect(encoded.rejected.mask.contains { $0 > 0 })
        #expect(tok.decode(encoded.chosen.ids).contains("chosen"))
        #expect(tok.decode(encoded.rejected.ids).contains("rejected"))
    }
}
