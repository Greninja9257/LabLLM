import Testing
import MLX
@testable import LabLLM

struct LossMaskingTests {
    private func ensureMLX() {
        try! MLXMetalLibrary.ensureAvailable()
    }

    @Test func maskedLanguageModelingLossIgnoresPaddingTargets() {
        ensureMLX()
        MLXRandom.seed(7)
        let tok = Tokenizer.character(from: "ab")
        var config = GPTConfig(vocabSize: tok.vocabSize, blockSize: 4, nEmbd: 16, nLayers: 1, nHeads: 2)
        config.dropout = 0
        let model = GPT(config)
        eval(model.parameters())

        let x = MLXArray(tok.encode("ab") + [tok.padID, tok.padID], [1, 4])
        let y = MLXArray(tok.encode("ba") + [tok.padID, tok.padID], [1, 4])
        let masked = maskedLanguageModelingLoss(model: model, x: x, y: y, padID: tok.padID)

        let xTrim = MLXArray(tok.encode("ab"), [1, 2])
        let yTrim = MLXArray(tok.encode("ba"), [1, 2])
        let expected = maskedLanguageModelingLoss(model: model, x: xTrim, y: yTrim, padID: tok.padID)
        eval(masked, expected)

        #expect(abs(masked.item(Float.self) - expected.item(Float.self)) < 1e-5)
    }

    @Test func allPaddingTargetsDoNotProduceNaN() {
        ensureMLX()
        MLXRandom.seed(8)
        let tok = Tokenizer.character(from: "a")
        var config = GPTConfig(vocabSize: tok.vocabSize, blockSize: 4, nEmbd: 16, nLayers: 1, nHeads: 2)
        config.dropout = 0
        let model = GPT(config)
        eval(model.parameters())

        let x = MLXArray(Array(repeating: tok.padID, count: 4), [1, 4])
        let y = MLXArray(Array(repeating: tok.padID, count: 4), [1, 4])
        let loss = maskedLanguageModelingLoss(model: model, x: x, y: y, padID: tok.padID)
        eval(loss)

        #expect(!loss.item(Float.self).isNaN)
        #expect(abs(loss.item(Float.self)) < 1e-6)
    }
}
