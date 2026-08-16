import Foundation
import MLX
import MLXNN

struct TrainingOptimizerSnapshot {
    var arrays: [String: MLXArray]
    var step: Int
}

final class TrainingOptimizer {
    let kind: OptimizerKind
    let weightDecay: Float
    private(set) var step: Int
    private var learningRate: Float
    private var adamM: [String: MLXArray] = [:]
    private var adamV: [String: MLXArray] = [:]

    init(config: TrainConfig, step: Int = 0) {
        self.kind = config.optimizer
        self.learningRate = config.learningRate
        self.weightDecay = config.weightDecay
        self.step = step
    }

    func setLearningRate(_ value: Float) {
        learningRate = value
    }

    func update(model: Module, gradients: ModuleParameters) {
        step += 1
        let parameters = Dictionary(uniqueKeysWithValues: model.parameters().flattened().map { ($0.0, $0.1) })
        var updated: [(String, MLXArray)] = []
        updated.reserveCapacity(gradients.flattened().count)

        for (key, gradient) in gradients.flattened() {
            guard let parameter = parameters[key] else { continue }
            switch kind {
            case .adamw:
                updated.append((key, adamWUpdate(key: key, parameter: parameter, gradient: gradient)))
            case .sgd:
                updated.append((key, sgdUpdate(parameter: parameter, gradient: gradient)))
            }
        }

        model.update(parameters: ModuleParameters.unflattened(updated))
    }

    func snapshot() -> TrainingOptimizerSnapshot {
        var arrays: [String: MLXArray] = [:]
        switch kind {
        case .adamw:
            for (key, value) in adamM { arrays["adam.m.\(key)"] = value }
            for (key, value) in adamV { arrays["adam.v.\(key)"] = value }
        case .sgd:
            break
        }
        return TrainingOptimizerSnapshot(arrays: arrays, step: step)
    }

    func restore(snapshot: TrainingOptimizerSnapshot) {
        step = snapshot.step
        adamM.removeAll()
        adamV.removeAll()
        for (key, value) in snapshot.arrays {
            if key.hasPrefix("adam.m.") {
                adamM[String(key.dropFirst("adam.m.".count))] = value
            } else if key.hasPrefix("adam.v.") {
                adamV[String(key.dropFirst("adam.v.".count))] = value
            }
        }
    }

    private func adamWUpdate(key: String, parameter: MLXArray, gradient: MLXArray) -> MLXArray {
        let beta1: Float = 0.9
        let beta2: Float = 0.999
        let eps: Float = 1e-8
        let decayedParameter = parameter * (1 - learningRate * weightDecay)
        let previousM = adamM[key] ?? MLXArray.zeros(like: parameter)
        let previousV = adamV[key] ?? MLXArray.zeros(like: parameter)
        let m = beta1 * previousM + (1 - beta1) * gradient
        let v = beta2 * previousV + (1 - beta2) * square(gradient)
        adamM[key] = m
        adamV[key] = v
        return decayedParameter - learningRate * m / (sqrt(v) + eps)
    }

    private func sgdUpdate(parameter: MLXArray, gradient: MLXArray) -> MLXArray {
        let adjustedGradient = weightDecay != 0 ? gradient + weightDecay * parameter : gradient
        return parameter - learningRate * adjustedGradient
    }
}
