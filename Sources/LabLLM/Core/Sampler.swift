import Foundation
import MLX

struct SamplingParams {
    var maxTokens: Int = 200
    var temperature: Float = 0.8
    var topK: Int = 0            // 0 = disabled
    var topP: Float = 1.0        // 1.0 = disabled (nucleus)
    var minP: Float = 0.0        // 0.0 = disabled
    var repetitionPenalty: Float = 1.0   // 1.0 = disabled
    var repetitionWindow: Int = 64
    var greedy: Bool = false
    var seed: UInt64? = nil
    var stopSequences: [String] = []
    var stopTokenIDs: [Int32] = []      // e.g. the <|end|> id for chat
}

struct XRayCandidate: Identifiable {
    let id = UUID()
    let tokenText: String
    let prob: Float
}

struct XRayStep: Identifiable {
    let id = UUID()
    let chosenText: String
    let chosenProb: Float
    let entropy: Float           // in nats, over the model's full raw distribution
    let candidates: [XRayCandidate]   // top-N by probability, includes the chosen token
}

enum Sampler {
    /// Generate autoregressively. Only the forward pass runs in MLX; all decoding
    /// (penalties, top-k/p, min-p, sampling) is plain Swift on the logits vector,
    /// which keeps it correct and easy to reason about. `onToken` streams pieces.
    static func generate(model: GPT,
                         tokenizer: Tokenizer,
                         prompt: String,
                         params: SamplingParams,
                         onToken: @escaping (String) -> Void) -> String {
        let promptIDs = tokenizer.encode(prompt)
        return generate(model: model, tokenizer: tokenizer, promptIDs: promptIDs, params: params, onToken: onToken)
    }

    /// Same generation loop as `generate`, but also reports, per step, the model's
    /// RAW distribution (before temperature/top-k/top-p filtering) — the chosen
    /// token's probability, the distribution's entropy, and its top-N candidates.
    /// The actual continuation still samples from the filtered distribution per
    /// `params`, so the generated text matches what you'd get from `generate`.
    static func generateTrace(model: GPT,
                              tokenizer: Tokenizer,
                              prompt: String,
                              params: SamplingParams,
                              topN: Int,
                              onStep: @escaping (XRayStep) -> Void) -> String {
        var rng: RandomNumberGenerator = params.seed.map { SeededGenerator(seed: $0) } ?? SystemRandomNumberGenerator()
        let blockSize = model.config.blockSize
        var ids = tokenizer.encode(prompt)
        if ids.isEmpty { ids = [0] }
        var generated = [Int32]()
        var tail = ""
        let stopSet = Set(params.stopTokenIDs)

        for _ in 0 ..< params.maxTokens {
            let context = Array(ids.suffix(blockSize))
            let x = MLXArray(context, [1, context.count])
            let out = model(x)
            let logitsMLX = out[0, context.count - 1]
            eval(logitsMLX)
            let rawLogits = logitsMLX.asArray(Float.self)
            let rawProbs = softmax(rawLogits)

            var filtered = rawLogits
            let nextID: Int32
            if params.greedy {
                nextID = Int32(argmax(filtered))
            } else {
                if params.repetitionPenalty != 1.0 {
                    applyRepetitionPenalty(&filtered, recent: ids.suffix(params.repetitionWindow), penalty: params.repetitionPenalty)
                }
                if params.temperature > 0 { for i in filtered.indices { filtered[i] /= params.temperature } }
                if params.topK > 0 { applyTopK(&filtered, k: params.topK) }
                var probs = softmax(filtered)
                if params.topP < 1.0 { applyTopP(&probs, p: params.topP) }
                if params.minP > 0.0 { applyMinP(&probs, minP: params.minP) }
                nextID = Int32(sample(probs, using: &rng))
            }

            // Entropy (nats) and top-N of the RAW distribution, for inspection.
            var entropy: Float = 0
            for p in rawProbs where p > 1e-9 { entropy -= p * logf(p) }
            let order = rawProbs.indices.sorted { rawProbs[$0] > rawProbs[$1] }.prefix(topN)
            let candidates = order.map { i in
                XRayCandidate(tokenText: tokenizer.decode([Int32(i)]), prob: rawProbs[i])
            }
            let chosenProb = rawProbs.indices.contains(Int(nextID)) ? rawProbs[Int(nextID)] : 0
            let chosenText = tokenizer.decode([nextID])
            onStep(XRayStep(chosenText: chosenText, chosenProb: chosenProb, entropy: entropy, candidates: Array(candidates)))

            if stopSet.contains(nextID) { break }
            ids.append(nextID); generated.append(nextID)
            tail = String((tail + chosenText).suffix(64))
            if stop(tail, params.stopSequences) { break }
        }
        return tokenizer.decode(generated)
    }

    /// Core loop, entered from either a plain-text prompt or pre-tokenized ids
    /// (chat uses the latter, since the prompt contains special tokens).
    static func generate(model: GPT,
                         tokenizer: Tokenizer,
                         promptIDs: [Int32],
                         params: SamplingParams,
                         onToken: @escaping (String) -> Void) -> String {

        var rng: RandomNumberGenerator = params.seed.map { SeededGenerator(seed: $0) } ?? SystemRandomNumberGenerator()
        let blockSize = model.config.blockSize

        var ids = promptIDs
        if ids.isEmpty { ids = [0] }
        var generated = [Int32]()
        var tail = ""
        let stopSet = Set(params.stopTokenIDs)

        for _ in 0 ..< params.maxTokens {
            let context = Array(ids.suffix(blockSize))
            let x = MLXArray(context, [1, context.count])
            let out = model(x)                                   // (1, L, V)
            let logitsMLX = out[0, context.count - 1]            // (V,)
            eval(logitsMLX)
            var logits = logitsMLX.asArray(Float.self)           // [V] in Swift

            let nextID: Int32
            if params.greedy {
                nextID = Int32(argmax(logits))
            } else {
                if params.repetitionPenalty != 1.0 {
                    applyRepetitionPenalty(&logits, recent: ids.suffix(params.repetitionWindow),
                                           penalty: params.repetitionPenalty)
                }
                if params.temperature > 0 { for i in logits.indices { logits[i] /= params.temperature } }
                if params.topK > 0 { applyTopK(&logits, k: params.topK) }
                var probs = softmax(logits)
                if params.topP < 1.0 { applyTopP(&probs, p: params.topP) }
                if params.minP > 0.0 { applyMinP(&probs, minP: params.minP) }
                nextID = Int32(sample(probs, using: &rng))
            }

            if stopSet.contains(nextID) { break }               // e.g. <|end|>
            emit(nextID, &ids, &generated, &tail, tokenizer, onToken)
            if stop(tail, params.stopSequences) { break }
        }
        return tokenizer.decode(generated)
    }

    // MARK: - Swift decoding math

    private static func emit(_ id: Int32, _ ids: inout [Int32], _ gen: inout [Int32],
                             _ tail: inout String, _ tok: Tokenizer, _ onToken: (String) -> Void) {
        ids.append(id); gen.append(id)
        let piece = tok.decode([id])
        tail = String((tail + piece).suffix(64))
        onToken(piece)
    }

    private static func stop(_ tail: String, _ stops: [String]) -> Bool {
        stops.contains { !$0.isEmpty && tail.hasSuffix($0) }
    }

    private static func argmax(_ v: [Float]) -> Int {
        guard !v.isEmpty else { return 0 }
        var best = 0; var bestV = -Float.greatestFiniteMagnitude
        for (i, x) in v.enumerated() where x > bestV { bestV = x; best = i }
        return best
    }

    private static func softmax(_ logits: [Float]) -> [Float] {
        guard !logits.isEmpty else { return [1] }
        let m = logits.max() ?? 0
        var exps = logits.map { expf($0 - m) }
        let sum = exps.reduce(0, +)
        if sum > 0 { for i in exps.indices { exps[i] /= sum } }
        return exps
    }

    private static func applyRepetitionPenalty(_ logits: inout [Float], recent: ArraySlice<Int32>, penalty: Float) {
        for t in Set(recent) {
            let i = Int(t)
            guard logits.indices.contains(i) else { continue }
            logits[i] = logits[i] > 0 ? logits[i] / penalty : logits[i] * penalty
        }
    }

    private static func applyTopK(_ logits: inout [Float], k: Int) {
        guard !logits.isEmpty else { return }
        guard k > 0, k < logits.count else { return }
        let threshold = logits.sorted(by: >)[k - 1]
        for i in logits.indices where logits[i] < threshold { logits[i] = -Float.greatestFiniteMagnitude }
    }

    private static func applyTopP(_ probs: inout [Float], p: Float) {
        guard !probs.isEmpty else { return }
        let order = probs.indices.sorted { probs[$0] > probs[$1] }
        var cum: Float = 0
        var keep = Set<Int>()
        for idx in order { cum += probs[idx]; keep.insert(idx); if cum >= p { break } }
        for i in probs.indices where !keep.contains(i) { probs[i] = 0 }
        renormalize(&probs)
    }

    private static func applyMinP(_ probs: inout [Float], minP: Float) {
        guard !probs.isEmpty else { return }
        let maxP = probs.max() ?? 0
        let floor = maxP * minP
        for i in probs.indices where probs[i] < floor { probs[i] = 0 }
        renormalize(&probs)
    }

    private static func renormalize(_ probs: inout [Float]) {
        let sum = probs.reduce(0, +)
        if sum > 0 { for i in probs.indices { probs[i] /= sum } }
    }

    private static func sample(_ probs: [Float], using rng: inout RandomNumberGenerator) -> Int {
        guard !probs.isEmpty else { return 0 }
        let r = Float.random(in: 0 ..< 1, using: &rng)
        var cum: Float = 0
        for (i, p) in probs.enumerated() { cum += p; if r < cum { return i } }
        return max(0, probs.count - 1)
    }
}

/// Small deterministic RNG so a fixed seed reproduces a generation (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
