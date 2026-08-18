import Foundation
import Testing
import MLX
import MLXNN
@testable import LabLLM

struct CheckpointResumeTests {
    private func ensureMLX() {
        try! MLXMetalLibrary.ensureAvailable()
    }

    @Test func adamWOptimizerSnapshotRestoresContinuousTrajectory() {
        ensureMLX()
        let tok = Tokenizer.character(from: "abcdef")
        var config = GPTConfig(vocabSize: tok.vocabSize, blockSize: 4, nEmbd: 16, nLayers: 1, nHeads: 2)
        config.dropout = 0
        MLXRandom.seed(123)
        let base = GPT(config)
        eval(base.parameters())

        let continuous = GPT(config)
        continuous.update(parameters: base.parameters())
        let resumed = GPT(config)
        resumed.update(parameters: base.parameters())

        var tc = TrainConfig(batchSize: 1, gradAccumSteps: 1, maxSteps: 2, optimizer: .adamw)
        tc.learningRate = 1e-3
        tc.weightDecay = 0.01
        let x = MLXArray(tok.encode("abcd"), [1, 4])
        let y = MLXArray(tok.encode("bcde"), [1, 4])

        let continuousOptimizer = TrainingOptimizer(config: tc)
        trainOneStep(model: continuous, optimizer: continuousOptimizer, x: x, y: y, padID: tok.padID, step: 1, config: tc)
        trainOneStep(model: continuous, optimizer: continuousOptimizer, x: x, y: y, padID: tok.padID, step: 2, config: tc)

        let firstOptimizer = TrainingOptimizer(config: tc)
        trainOneStep(model: resumed, optimizer: firstOptimizer, x: x, y: y, padID: tok.padID, step: 1, config: tc)
        let restoredOptimizer = TrainingOptimizer(config: tc)
        restoredOptimizer.restore(snapshot: firstOptimizer.snapshot())
        trainOneStep(model: resumed, optimizer: restoredOptimizer, x: x, y: y, padID: tok.padID, step: 2, config: tc)

        assertParametersClose(continuous.parameters(), resumed.parameters(), tolerance: 1e-5)
        #expect(restoredOptimizer.snapshot().step == 2)
    }

    @Test func checkpointPersistsOptimizerAndTrainingState() throws {
        ensureMLX()
        let tok = Tokenizer.character(from: "abcdef")
        var config = GPTConfig(vocabSize: tok.vocabSize, blockSize: 4, nEmbd: 16, nLayers: 1, nHeads: 2)
        config.dropout = 0
        MLXRandom.seed(456)
        let model = GPT(config)
        eval(model.parameters())

        var tc = TrainConfig(batchSize: 1, gradAccumSteps: 1, maxSteps: 2, optimizer: .adamw)
        tc.learningRate = 1e-3
        let optimizer = TrainingOptimizer(config: tc)
        let x = MLXArray(tok.encode("abcd"), [1, 4])
        let y = MLXArray(tok.encode("bcde"), [1, 4])
        trainOneStep(model: model, optimizer: optimizer, x: x, y: y, padID: tok.padID, step: 1, config: tc)

        let snapshot = optimizer.snapshot()
        let meta = Checkpoint.Meta(
            config: config,
            tokenizer: tok,
            step: 1,
            loss: 1.25,
            valLoss: 1.5,
            createdAt: Date(timeIntervalSince1970: 0),
            method: "Pretraining",
            datasetName: "unit-test",
            trainingConfig: tc,
            optimizerStep: snapshot.step,
            trainRNGState: 999,
            checkpointFormatVersion: 2
        )
        let name = "unit-test-\(UUID().uuidString)"
        // Saved into a scratch folder so this test never depends on which model
        // workspace happens to be active.
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("LabLLMCheckpointTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let dir = try Checkpoint.save(model: model, meta: meta, name: name, hardware: nil, optimizerSnapshot: snapshot, in: parent)

        let loadedMeta = try Checkpoint.loadMeta(from: dir)
        let loadedSnapshot = try #require(try Checkpoint.loadOptimizerSnapshot(from: dir, step: loadedMeta.optimizerStep ?? 0))

        #expect(loadedMeta.step == 1)
        #expect(loadedMeta.optimizerStep == 1)
        #expect(loadedMeta.trainRNGState == 999)
        #expect(loadedMeta.trainingConfig == tc)
        #expect(!loadedSnapshot.arrays.isEmpty)
        #expect(loadedSnapshot.step == 1)
    }

    private func trainOneStep(model: GPT, optimizer: TrainingOptimizer, x: MLXArray, y: MLXArray,
                              padID: Int32, step: Int, config: TrainConfig) {
        let lossAndGrad = valueAndGrad { (parameters: ModuleParameters, arrays: [MLXArray]) -> [MLXArray] in
            model.update(parameters: parameters)
            return [maskedLanguageModelingLoss(model: model, x: arrays[0], y: arrays[1], padID: padID)]
        }
        optimizer.setLearningRate(lrSchedule(step: step, tc: config))
        let (_, grads) = lossAndGrad(model.trainableParameters(), [x, y])
        optimizer.update(model: model, gradients: grads)
        eval(model)
    }

    private func lrSchedule(step: Int, tc: TrainConfig) -> Float {
        if step < tc.warmupSteps { return tc.learningRate * Float(step) / Float(max(tc.warmupSteps, 1)) }
        let progress = Double(step - tc.warmupSteps) / Double(max(tc.maxSteps - tc.warmupSteps, 1))
        let cosine = Float(0.5 * (1 + Foundation.cos(Double.pi * min(progress, 1.0))))
        return tc.minLearningRate + (tc.learningRate - tc.minLearningRate) * cosine
    }

    private func assertParametersClose(_ lhs: ModuleParameters, _ rhs: ModuleParameters, tolerance: Float) {
        let rhsMap = Dictionary(uniqueKeysWithValues: rhs.flattened().map { ($0.0, $0.1) })
        for (key, leftArray) in lhs.flattened() {
            let rightArray = rhsMap[key]!
            eval(leftArray, rightArray)
            let left = leftArray.asArray(Float.self)
            let right = rightArray.asArray(Float.self)
            #expect(left.count == right.count)
            for (a, b) in zip(left, right) {
                let delta = a > b ? a - b : b - a
                #expect(delta < tolerance)
            }
        }
    }
}
