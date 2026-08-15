import Foundation
import MLX
import MLXNN
import MLXOptimizers
import MLXRandom
import Combine

enum OptimizerKind: String, Codable, CaseIterable, Identifiable {
    case adamw, sgd
    var id: String { rawValue }
    var label: String { self == .adamw ? "AdamW" : "SGD" }
}

/// Hyperparameters for a training run (pretrain, SFT, or DPO). Editable in the
/// Training view.
struct TrainConfig: Codable, Equatable {
    var batchSize: Int = 32
    var gradAccumSteps: Int = 1
    var maxSteps: Int = 2000
    var optimizer: OptimizerKind = .adamw
    var learningRate: Float = 3e-4
    var minLearningRate: Float = 3e-5
    var warmupSteps: Int = 100
    var weightDecay: Float = 0.1
    var gradClip: Float = 1.0
    var evalEvery: Int = 100
    var sampleEvery: Int = 250
    var checkpointEvery: Int = 500     // periodic full save during a run, not just at the end
    var seed: UInt64 = 42

    // LoRA (used only when Trainer.startSFT(useLoRA: true) is called)
    var loraRank: Int = 8
    var loraAlpha: Float = 16

    // DPO
    var dpoBeta: Float = 0.1
}

struct LossPoint: Identifiable {
    let id = UUID()
    let step: Int
    let value: Double
    let kind: Kind
    enum Kind { case train, val }
}

struct TrainingSample: Identifiable {
    let id = UUID()
    let step: Int
    let text: String
    let method: String
    let createdAt = Date()
}

private struct TrainingFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Owns a training run. Heavy compute happens on a background serial queue; all
/// @Published mutations are marshalled to the main queue for SwiftUI.
final class Trainer: ObservableObject {
    @Published var isTraining = false
    @Published var isPaused = false
    @Published var step = 0
    @Published var maxSteps = 0
    @Published var trainLoss: Double = 0
    @Published var valLoss: Double = 0
    @Published var tokensPerSec: Double = 0
    @Published var etaSeconds: Double = 0
    @Published var currentLR: Double = 0
    @Published var lossHistory: [LossPoint] = []
    @Published var liveSample: String = ""
    @Published var sampleHistory: [TrainingSample] = []
    @Published var statusMessage: String = "Idle"
    @Published var errorMessage: String? = nil
    @Published var lastCheckpointDir: URL? = nil
    @Published var runIsLoRA = false

    var progress: Double {
        guard maxSteps > 0 else { return 0 }
        return min(max(Double(step) / Double(maxSteps), 0), 1)
    }

    @Published var hasModel = false
    @Published var isSampling = false
    @Published var sampleOutput = ""

    @Published var isChatting = false
    @Published var chatStreaming = ""

    @Published var isXraying = false
    @Published var xraySteps: [XRayStep] = []

    private(set) var model: GPT?
    private(set) var tokenizer: Tokenizer?

    private let queue = DispatchQueue(label: "com.labllm.training", qos: .userInitiated)
    private var stopRequested = false
    private var pauseRequested = false
    /// Signaled when a training session's post-loop save has finished, so the app
    /// delegate can block app termination just long enough for progress to be saved.
    private var doneSemaphore = DispatchSemaphore(value: 0)

    // MARK: - Control

    func pause() { pauseRequested = true; publish { self.isPaused = true; self.statusMessage = "Paused" } }
    func resume() { pauseRequested = false; publish { self.isPaused = false; self.statusMessage = "Training" } }
    func stop() { stopRequested = true }

    /// Called from the app delegate on Cmd+Q / quit. If a run is active, stops it
    /// and waits (bounded) for the in-flight checkpoint save to finish so progress
    /// isn't lost. Returns true if it's safe to terminate now.
    func requestGracefulShutdown(timeout: TimeInterval = 8) -> Bool {
        guard isTraining else { return true }
        stopRequested = true
        return doneSemaphore.wait(timeout: .now() + timeout) == .success
    }

    // MARK: - Pretraining

    func start(gptConfig: GPTConfig, trainConfig: TrainConfig, tokenizer: Tokenizer, corpus: String,
              hardware: HardwareInfo, datasetName: String?, resumeFrom: URL? = nil) {
        guard !isTraining else { return }
        beginSession(maxSteps: trainConfig.maxSteps, statusMessage: "Preparing…")
        queue.async {
            self.run(gptConfig, trainConfig, tokenizer, corpus, hardware, datasetName, resumeFrom)
            self.doneSemaphore.signal()
        }
    }

    private func run(_ gptConfig: GPTConfig, _ tc: TrainConfig, _ tokenizer: Tokenizer, _ corpus: String,
                     _ hardware: HardwareInfo, _ datasetName: String?, _ resumeFrom: URL?) {
        MLXRandom.seed(tc.seed)
        var config = gptConfig
        config.vocabSize = tokenizer.vocabSize

        let model: GPT
        if let resumeFrom, let meta = try? Checkpoint.loadMeta(from: resumeFrom),
           let loaded = try? Checkpoint.loadModel(from: resumeFrom, meta: meta) {
            model = loaded
            publish { self.statusMessage = "Resumed from \(resumeFrom.lastPathComponent)" }
        } else {
            model = GPT(config); eval(model.parameters())
        }

        let dataset = TextDataset(text: corpus, tokenizer: tokenizer, blockSize: config.blockSize)
        let (optimizer, setLR) = makeOptimizer(tc)
        let lossAndGrad = valueAndGrad(model: model, languageModelingLoss)

        self.model = model; self.tokenizer = tokenizer
        publish { self.hasModel = true; self.statusMessage = "Training" }
        let startTime = Date(); var lastReport = Date()

        for s in 1 ... tc.maxSteps {
            if stopRequested { break }
            while pauseRequested && !stopRequested { Thread.sleep(forTimeInterval: 0.1) }
            if stopRequested { break }

            let lrNow = lrSchedule(step: s, tc: tc); setLR(lrNow)
            let accumSteps = max(tc.gradAccumSteps, 1)
            var accum: ModuleParameters? = nil
            var lossSum: Float = 0
            for _ in 0 ..< accumSteps {
                let (x, y) = dataset.batch(batchSize: tc.batchSize)
                let (loss, grads) = lossAndGrad(model, x, y)
                lossSum += loss.item(Float.self)
                accum = (accum == nil) ? grads : addParams(accum!, grads)
            }
            let denom = Float(accumSteps)
            var finalGrads = accumSteps > 1 ? accum!.mapValues { $0 / denom } : accum!
            if tc.gradClip > 0 { finalGrads = clipGradNorm(finalGrads, maxNorm: tc.gradClip) }
            optimizer.update(model: model, gradients: finalGrads)
            eval(model, optimizer)

            let lossValue = lossSum / denom
            reportStep(s, tc, lossValue, lrNow, tokens: tc.batchSize * config.blockSize * accumSteps,
                      lastReport: &lastReport, startTime: startTime)

            if shouldEvaluate(step: s, config: tc) {
                let vl = estimateValLoss(model: model, dataset: dataset, batchSize: tc.batchSize)
                publish { self.valLoss = Double(vl); self.lossHistory.append(LossPoint(step: s, value: Double(vl), kind: .val)) }
            }
            if s % tc.sampleEvery == 0 { emitLiveSample(model: model, tokenizer: tokenizer, step: s, method: "Pretraining") }
            if s % tc.checkpointEvery == 0 {
                saveCheckpoint(model: model, config: config, tokenizer: tokenizer, step: s,
                              loss: lossValue, valLoss: Float(valLoss), method: "Pretraining",
                              datasetName: datasetName, hardware: hardware, name: "pretrain-\(s)-\(Int(Date().timeIntervalSince1970))")
            }
        }

        let final = saveCheckpoint(model: model, config: config, tokenizer: tokenizer, step: self.step,
                                   loss: Float(trainLoss), valLoss: Float(valLoss), method: "Pretraining",
                                   datasetName: datasetName, hardware: hardware,
                                   name: "pretrain-final-\(Int(Date().timeIntervalSince1970))")
        publish {
            self.isTraining = false
            self.statusMessage = self.stopRequested ? "Stopped at step \(self.step) — progress saved"
                : "Training done" + (final != nil ? " — checkpoint saved" : "")
        }
    }

    // MARK: - Supervised fine-tuning (chat), with optional LoRA

    func startSFT(gptConfig: GPTConfig, trainConfig tc: TrainConfig, tokenizer: Tokenizer,
                 conversations: [[ChatMessage]], useLoRA: Bool, hardware: HardwareInfo,
                 datasetName: String?, resumeFrom: URL? = nil) {
        guard !isTraining else { return }
        beginSession(maxSteps: tc.maxSteps, statusMessage: "Preparing fine-tuning…")
        queue.async {
            self.runSFT(gptConfig, tc, tokenizer, conversations, useLoRA, hardware, datasetName, resumeFrom)
            self.doneSemaphore.signal()
        }
    }

    private func runSFT(_ gptConfig: GPTConfig, _ tc: TrainConfig, _ tokenizer: Tokenizer,
                        _ conversations: [[ChatMessage]], _ useLoRA: Bool, _ hardware: HardwareInfo,
                        _ datasetName: String?, _ resumeFrom: URL?) {
        MLXRandom.seed(tc.seed)
        var config = gptConfig
        config.vocabSize = tokenizer.vocabSize

        let model: GPT
        if let resumeFrom, let meta = try? Checkpoint.loadMeta(from: resumeFrom),
           let loaded = try? Checkpoint.loadModel(from: resumeFrom, meta: meta) {
            model = loaded
        } else if let existing = self.model, existing.config.vocabSize == config.vocabSize,
                  existing.config.nEmbd == config.nEmbd, existing.config.nLayers == config.nLayers {
            model = existing
        } else {
            model = GPT(config); eval(model.parameters())
        }
        if useLoRA && !model.hasLoRA { model.addLoRA(rank: tc.loraRank, alpha: tc.loraAlpha) }
        publish { self.runIsLoRA = model.hasLoRA }

        let dataset = SFTDataset(conversations: conversations, tokenizer: tokenizer, blockSize: config.blockSize)
        let (optimizer, setLR) = makeOptimizer(tc)
        let padID = tokenizer.padID
        let sftVG = valueAndGrad { (parameters: ModuleParameters, arrays: [MLXArray]) -> [MLXArray] in
            model.update(parameters: parameters)
            guard arrays.count >= 2 else { return [] }
            return [self.sftLoss(model: model, x: arrays[0], y: arrays[1], padID: padID)]
        }

        self.model = model; self.tokenizer = tokenizer
        publish { self.hasModel = true; self.statusMessage = model.hasLoRA ? "Fine-tuning (LoRA)" : "Fine-tuning (full)" }
        let startTime = Date(); var lastReport = Date()

        let maxSteps = max(1, tc.maxSteps)
        let sampleEvery = max(1, tc.sampleEvery)
        let checkpointEvery = max(1, tc.checkpointEvery)

        for s in 1 ... maxSteps {
            if stopRequested { break }
            while pauseRequested && !stopRequested { Thread.sleep(forTimeInterval: 0.1) }
            if stopRequested { break }

            let lrNow = lrSchedule(step: s, tc: tc); setLR(lrNow)
            let (x, y) = dataset.batch(batchSize: tc.batchSize)
            let loss: MLXArray
            let grads: ModuleParameters
            do {
                // MLX raises C++ errors from value-and-grad through a callback.
                // Scope it so malformed SFT batches become an in-app error instead
                // of terminating the whole macOS process.
                let result = try withError { () throws -> ([MLXArray], ModuleParameters) in
                    let (values, gradients) = sftVG(model.trainableParameters(), [x, y])
                    guard !values.isEmpty else {
                        throw TrainingFailure(message: "MLX returned no SFT loss. Try disabling LoRA for this run or reducing batch/context size.")
                    }
                    return (values, gradients)
                }
                loss = result.0[0]
                grads = result.1
            } catch {
                publish {
                    self.errorMessage = "Fine-tuning stopped: \(error.localizedDescription)"
                    self.statusMessage = "Fine-tuning needs attention"
                }
                break
            }
            let finalGrads = tc.gradClip > 0 ? clipGradNorm(grads, maxNorm: tc.gradClip) : grads
            optimizer.update(model: model, gradients: finalGrads)
            eval(model, optimizer)

            let lossValue = loss.item(Float.self)
            reportStep(s, tc, lossValue, lrNow, tokens: tc.batchSize * config.blockSize,
                      lastReport: &lastReport, startTime: startTime)

            if shouldEvaluate(step: s, config: tc), dataset.hasValidationSplit {
                let vl = estimateSFTValLoss(model: model, dataset: dataset, batchSize: tc.batchSize)
                publish { self.valLoss = Double(vl); self.lossHistory.append(LossPoint(step: s, value: Double(vl), kind: .val)) }
            }
            if s % sampleEvery == 0 { emitLiveSample(model: model, tokenizer: tokenizer, step: s, method: "Fine-tuning") }

            if s % checkpointEvery == 0 {
                saveCheckpoint(model: model, config: config, tokenizer: tokenizer, step: s, loss: lossValue,
                              valLoss: Float(valLoss), method: model.hasLoRA ? "SFT (LoRA)" : "SFT (full)",
                              datasetName: datasetName, hardware: hardware,
                              name: "sft-\(s)-\(Int(Date().timeIntervalSince1970))",
                              loraRank: model.hasLoRA ? tc.loraRank : nil, loraAlpha: model.hasLoRA ? tc.loraAlpha : nil)
            }
        }

        let final = saveCheckpoint(model: model, config: config, tokenizer: tokenizer, step: self.step,
                                   loss: Float(trainLoss), valLoss: Float(valLoss),
                                   method: model.hasLoRA ? "SFT (LoRA)" : "SFT (full)", datasetName: datasetName,
                                   hardware: hardware, name: "sft-final-\(Int(Date().timeIntervalSince1970))",
                                   loraRank: model.hasLoRA ? tc.loraRank : nil, loraAlpha: model.hasLoRA ? tc.loraAlpha : nil)
        publish {
            self.isTraining = false
            self.statusMessage = self.stopRequested ? "Stopped at step \(self.step) — progress saved"
                : "Fine-tuning done" + (final != nil ? " — checkpoint saved" : "")
        }
    }

    // MARK: - DPO (preference training)

    func startDPO(trainConfig tc: TrainConfig, examples: [PreferenceExample], hardware: HardwareInfo) {
        guard !isTraining, let policyBase = model, let tokenizer = tokenizer else {
            publish { self.errorMessage = "DPO needs a fine-tuned model in memory first — run SFT, then DPO." }
            return
        }
        beginSession(maxSteps: tc.maxSteps, statusMessage: "Preparing DPO…")
        queue.async {
            self.runDPO(tc, examples, policyBase, tokenizer, hardware)
            self.doneSemaphore.signal()
        }
    }

    private func runDPO(_ tc: TrainConfig, _ examples: [PreferenceExample], _ policy: GPT,
                        _ tokenizer: Tokenizer, _ hardware: HardwareInfo) {
        MLXRandom.seed(tc.seed)
        // Frozen reference model: a fresh copy of the policy's current weights,
        // never updated again. DPO compares the policy's shift away from it.
        let reference = GPT(policy.config)
        reference.update(parameters: policy.parameters())
        eval(reference); reference.freeze()

        let dataset = DPODataset(examples: examples, tokenizer: tokenizer, blockSize: policy.config.blockSize)
        let (optimizer, setLR) = makeOptimizer(tc)
        let beta = tc.dpoBeta

        let dpoVG = valueAndGrad(model: policy) { (m: GPT, arrs: [MLXArray]) -> [MLXArray] in
            [self.dpoLoss(policy: m, reference: reference,
                          chosen: (arrs[0], arrs[1], arrs[2]), rejected: (arrs[3], arrs[4], arrs[5]), beta: beta)]
        }

        publish { self.statusMessage = "DPO training" }
        let startTime = Date(); var lastReport = Date()

        for s in 1 ... tc.maxSteps {
            if stopRequested { break }
            while pauseRequested && !stopRequested { Thread.sleep(forTimeInterval: 0.1) }
            if stopRequested { break }

            let lrNow = lrSchedule(step: s, tc: tc); setLR(lrNow)
            let (chosen, rejected) = dataset.batch(batchSize: tc.batchSize)
            let args = [chosen.0, chosen.1, chosen.2, rejected.0, rejected.1, rejected.2]
            let (vals, grads) = dpoVG(policy, args)
            let finalGrads = tc.gradClip > 0 ? clipGradNorm(grads, maxNorm: tc.gradClip) : grads
            optimizer.update(model: policy, gradients: finalGrads)
            eval(policy, optimizer)

            let lossValue = vals[0].item(Float.self)
            reportStep(s, tc, lossValue, lrNow, tokens: tc.batchSize * policy.config.blockSize * 2,
                      lastReport: &lastReport, startTime: startTime)

            if s % tc.checkpointEvery == 0 {
                saveCheckpoint(model: policy, config: policy.config, tokenizer: tokenizer, step: s, loss: lossValue,
                              valLoss: 0, method: "DPO", datasetName: "Preference pairs", hardware: hardware,
                              name: "dpo-\(s)-\(Int(Date().timeIntervalSince1970))")
            }
        }

        let final = saveCheckpoint(model: policy, config: policy.config, tokenizer: tokenizer, step: self.step,
                                   loss: Float(trainLoss), valLoss: 0, method: "DPO", datasetName: "Preference pairs",
                                   hardware: hardware, name: "dpo-final-\(Int(Date().timeIntervalSince1970))")
        publish {
            self.isTraining = false
            self.statusMessage = self.stopRequested ? "Stopped at step \(self.step) — progress saved"
                : "DPO done" + (final != nil ? " — checkpoint saved" : "")
        }
    }

    /// DPO loss (Rafailov et al.): -log σ(β · [(logπ_c − logref_c) − (logπ_r − logref_r)]),
    /// where logπ/logref are summed log-probs over the assistant-only masked tokens.
    /// Built from crossEntropy + basic ops only, avoiding any unverified log-sigmoid API.
    func dpoLoss(policy: GPT, reference: GPT,
                chosen: (MLXArray, MLXArray, MLXArray), rejected: (MLXArray, MLXArray, MLXArray),
                beta: Float) -> MLXArray {
        func sumLogProb(_ model: GPT, _ x: MLXArray, _ y: MLXArray, _ w: MLXArray) -> MLXArray {
            let logits = model(x)
            let B = logits.dim(0), L = logits.dim(1), V = logits.dim(2)
            let nll = crossEntropy(logits: logits.reshaped([B * L, V]), targets: y.reshaped([B * L]), reduction: .none)
            let wt = w.reshaped([B * L])
            return -(nll * wt).sum()   // sum of log-probs over masked (assistant) tokens
        }
        let logpiC = sumLogProb(policy, chosen.0, chosen.1, chosen.2)
        let logpiR = sumLogProb(policy, rejected.0, rejected.1, rejected.2)
        let logrefC = sumLogProb(reference, chosen.0, chosen.1, chosen.2)
        let logrefR = sumLogProb(reference, rejected.0, rejected.1, rejected.2)

        let z = MLXArray(beta) * ((logpiC - logrefC) - (logpiR - logrefR))
        // Numerically stable -log(sigmoid(z)) == softplus(-z) == max(-z,0) + log(1+exp(-|z|))
        let negZ = -z
        let absZ = sqrt(z * z)
        let loss = maximum(negZ, MLXArray(Float(0))) + log(1 + exp(-absZ))
        return loss
    }

    /// Cross-entropy averaged over ONLY assistant target tokens. SFTDataset marks
    /// context targets as padID so the mask stays inside this typed loss function.
    func sftLoss(model: GPT, x: MLXArray, y: MLXArray, padID: Int32) -> MLXArray {
        let logits = model(x)
        let B = logits.dim(0), L = logits.dim(1), V = logits.dim(2)
        let flat = logits.reshaped([B * L, V])
        let tgt = y.reshaped([B * L])
        let wt = (tgt .!= padID).asType(Float.self)
        let perTok = crossEntropy(logits: flat, targets: tgt, reduction: .none)
        return (perTok * wt).sum() / maximum(wt.sum(), MLXArray(Float(1e-6)))
    }

    // MARK: - Checkpoint loading for sampling

    func loadForSampling(model: GPT, tokenizer: Tokenizer) {
        self.model = model
        self.tokenizer = tokenizer
        publish { self.hasModel = true; self.runIsLoRA = model.hasLoRA; self.statusMessage = "Loaded checkpoint" }
    }

    // MARK: - Chat

    func chat(system: String, history: [ChatMessage], params p: SamplingParams,
             onDone: @escaping (String) -> Void) {
        guard let model = model, let tok = tokenizer, !isChatting else { return }
        var params = p
        params.stopTokenIDs = [tok.endID]
        let promptIDs = ChatTemplate.encodePrompt(system: system, history: history, tok: tok)
        publish { self.isChatting = true; self.chatStreaming = "" }
        queue.async {
            let full = Sampler.generate(model: model, tokenizer: tok, promptIDs: promptIDs, params: params) { piece in
                self.publish { self.chatStreaming += piece }
            }
            self.publish { self.isChatting = false; onDone(full) }
        }
    }

    // MARK: - Sampling

    func sample(prompt: String, params: SamplingParams) {
        guard let model = model, let tok = tokenizer, !isSampling else { return }
        publish { self.isSampling = true; self.sampleOutput = prompt }
        queue.async {
            _ = Sampler.generate(model: model, tokenizer: tok, prompt: prompt, params: params) { piece in
                self.publish { self.sampleOutput += piece }
            }
            self.publish { self.isSampling = false }
        }
    }

    func continueSample(params: SamplingParams) {
        guard !sampleOutput.isEmpty else { return }
        sample(prompt: sampleOutput, params: params)
    }

    /// X-ray generation: same as sample(), but also records per-token probability,
    /// entropy, and top-N alternatives so the UI can show why each token was chosen.
    func xrayGenerate(prompt: String, params: SamplingParams, topN: Int = 8) {
        guard let model = model, let tok = tokenizer, !isXraying else { return }
        publish { self.isXraying = true; self.xraySteps = [] }
        queue.async {
            _ = Sampler.generateTrace(model: model, tokenizer: tok, prompt: prompt, params: params, topN: topN) { step in
                self.publish { self.xraySteps.append(step) }
            }
            self.publish { self.isXraying = false }
        }
    }

    // MARK: - Local model server (synchronous — called from ModelServer's connection queue)

    /// Runs generation directly on the calling thread rather than the training
    /// queue, so a slow HTTP client doesn't block the training/sampling pipeline.
    /// Guarded by `!isTraining` at the call site in ModelServer.
    func serverComplete(system: String, history: [ChatMessage], maxTokens: Int, temperature: Float) -> String? {
        guard let model = model, let tok = tokenizer else { return nil }
        let promptIDs = ChatTemplate.encodePrompt(system: system, history: history, tok: tok)
        var params = SamplingParams(maxTokens: maxTokens, temperature: temperature)
        params.stopTokenIDs = [tok.endID]
        return Sampler.generate(model: model, tokenizer: tok, promptIDs: promptIDs, params: params) { _ in }
    }

    func serverStream(system: String, history: [ChatMessage], maxTokens: Int, temperature: Float,
                      onToken: @escaping (String) -> Void) -> Bool {
        guard let model = model, let tok = tokenizer else { return false }
        let promptIDs = ChatTemplate.encodePrompt(system: system, history: history, tok: tok)
        var params = SamplingParams(maxTokens: maxTokens, temperature: temperature)
        params.stopTokenIDs = [tok.endID]
        _ = Sampler.generate(model: model, tokenizer: tok, promptIDs: promptIDs, params: params, onToken: onToken)
        return true
    }

    // MARK: - Shared helpers

    private func beginSession(maxSteps: Int, statusMessage: String) {
        stopRequested = false; pauseRequested = false
        errorMessage = nil
        doneSemaphore = DispatchSemaphore(value: 0)
        publish {
            self.isTraining = true; self.isPaused = false; self.step = 0
            self.maxSteps = maxSteps; self.lossHistory = []; self.liveSample = ""; self.sampleHistory = []; self.valLoss = 0
            self.statusMessage = statusMessage; self.errorMessage = nil
        }
    }

    private func makeOptimizer(_ tc: TrainConfig) -> (Optimizer, (Float) -> Void) {
        switch tc.optimizer {
        case .adamw:
            let o = AdamW(learningRate: tc.learningRate, weightDecay: tc.weightDecay)
            return (o, { o.learningRate = $0 })
        case .sgd:
            let o = SGD(learningRate: tc.learningRate, weightDecay: tc.weightDecay)
            return (o, { o.learningRate = $0 })
        }
    }

    private func reportStep(_ s: Int, _ tc: TrainConfig, _ lossValue: Float, _ lrNow: Float, tokens: Int,
                            lastReport: inout Date, startTime: Date) {
        let dt = Date().timeIntervalSince(lastReport); lastReport = Date()
        let tps = dt > 0 ? Double(tokens) / dt : 0
        let secPerStep = Date().timeIntervalSince(startTime) / Double(s)
        publish {
            self.step = s; self.trainLoss = Double(lossValue); self.currentLR = Double(lrNow)
            self.tokensPerSec = tps; self.etaSeconds = Double(tc.maxSteps - s) * secPerStep
            self.lossHistory.append(LossPoint(step: s, value: Double(lossValue), kind: .train))
            if self.lossHistory.count > 4000 { self.lossHistory.removeFirst() }
        }
    }

    /// Cap the interval so a normal short run has enough validation samples to
    /// render a real curve rather than a lone point at the end.
    private func shouldEvaluate(step: Int, config: TrainConfig) -> Bool {
        let visualInterval = max(1, config.maxSteps / 12)
        let interval = max(1, min(config.evalEvery, visualInterval))
        return step == 1 || step == config.maxSteps || step % interval == 0
    }

    private func emitLiveSample(model: GPT, tokenizer: Tokenizer, step: Int, method: String) {
        let text = Sampler.generate(model: model, tokenizer: tokenizer, prompt: "\n",
                                    params: SamplingParams(maxTokens: 120, temperature: 0.8)) { _ in }
        publish {
            self.liveSample = text
            self.sampleHistory.append(TrainingSample(step: step, text: text, method: method))
        }
    }

    @discardableResult
    private func saveCheckpoint(model: GPT, config: GPTConfig, tokenizer: Tokenizer, step: Int, loss: Float,
                                valLoss: Float, method: String, datasetName: String?, hardware: HardwareInfo,
                                name: String, loraRank: Int? = nil, loraAlpha: Float? = nil) -> URL? {
        let meta = Checkpoint.Meta(config: config, tokenizer: tokenizer, step: step, loss: loss, valLoss: valLoss,
                                   createdAt: Date(), method: method, datasetName: datasetName,
                                   loraRank: loraRank, loraAlpha: loraAlpha)
        do {
            let dir = try Checkpoint.save(model: model, meta: meta, name: name, hardware: hardware)
            publish { self.lastCheckpointDir = dir }
            return dir
        } catch {
            publish { self.errorMessage = "Couldn't save checkpoint: \(error.localizedDescription)" }
            return nil
        }
    }

    private func lrSchedule(step: Int, tc: TrainConfig) -> Float {
        if step < tc.warmupSteps { return tc.learningRate * Float(step) / Float(max(tc.warmupSteps, 1)) }
        let progress = Double(step - tc.warmupSteps) / Double(max(tc.maxSteps - tc.warmupSteps, 1))
        let cosine = Float(0.5 * (1 + Foundation.cos(Double.pi * min(progress, 1.0))))
        return tc.minLearningRate + (tc.learningRate - tc.minLearningRate) * cosine
    }

    private func estimateValLoss(model: GPT, dataset: TextDataset, batchSize: Int, batches: Int = 5) -> Float {
        var total: Float = 0
        for _ in 0 ..< batches {
            let (x, y) = dataset.batch(batchSize: batchSize, validation: true)
            let l = languageModelingLoss(model: model, x: x, y: y)
            eval(l)
            total += l.item(Float.self)
        }
        return total / Float(batches)
    }

    private func estimateSFTValLoss(model: GPT, dataset: SFTDataset, batchSize: Int, batches: Int = 5) -> Float {
        var total: Float = 0
        for _ in 0 ..< batches {
            let (x, y) = dataset.batch(batchSize: batchSize, validation: true)
            let loss = sftLoss(model: model, x: x, y: y, padID: dataset.padID)
            eval(loss)
            total += loss.item(Float.self)
        }
        return total / Float(batches)
    }

    private func addParams(_ a: ModuleParameters, _ b: ModuleParameters) -> ModuleParameters {
        let bDict = Dictionary(uniqueKeysWithValues: b.flattened().map { ($0.0, $0.1) })
        let summed = a.flattened().map { (k, v) -> (String, MLXArray) in (k, v + (bDict[k] ?? v)) }
        return ModuleParameters.unflattened(summed)
    }

    private func clipGradNorm(_ grads: ModuleParameters, maxNorm: Float) -> ModuleParameters {
        var sumSq = MLXArray(Float(0))
        for (_, g) in grads.flattened() { sumSq = sumSq + (g * g).sum() }
        let norm = sqrt(sumSq)
        eval(norm)
        let n = norm.item(Float.self)
        guard n > maxNorm, n > 0 else { return grads }
        let scale = maxNorm / n
        return grads.mapValues { $0 * scale }
    }

    private func publish(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }
}
