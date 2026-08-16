import Foundation
import MLX
import MLXNN
import MLXFast

// MARK: - Model configuration

/// A fully editable GPT-style decoder configuration. Every field here maps to a
/// control in the Model Builder view, so the UI is just a thin editor over this.
struct GPTConfig: Codable, Equatable {
    var vocabSize: Int = 256          // set by the tokenizer after it's built
    var blockSize: Int = 128          // context length
    var nEmbd: Int = 256              // hidden / model dimension
    var nLayers: Int = 6
    var nHeads: Int = 8
    var mlpRatio: Int = 4             // feed-forward = nEmbd * mlpRatio
    var dropout: Float = 0.0
    var tieWeights: Bool = true       // share token-embedding & output projection
    var rmsEps: Float = 1e-5

    /// Rough (non-embedding-adjusted) parameter estimate for the resource panel.
    var estimatedParameters: Int {
        let ffn = nEmbd * nEmbd * mlpRatio * 2
        let attn = nEmbd * nEmbd * 4
        let perLayer = ffn + attn
        let embed = vocabSize * nEmbd + blockSize * nEmbd
        let head = tieWeights ? 0 : vocabSize * nEmbd
        return perLayer * nLayers + embed + head
    }

    /// Human validation errors surfaced before the user is allowed to train.
    var validationErrors: [String] {
        var e: [String] = []
        if nEmbd % nHeads != 0 { e.append("Hidden dim (\(nEmbd)) must be divisible by heads (\(nHeads)).") }
        if nLayers < 1 { e.append("Need at least 1 layer.") }
        if blockSize < 8 { e.append("Context length is very small (< 8).") }
        return e
    }
}

// MARK: - Building blocks

private func gelu(_ x: MLXArray) -> MLXArray {
    // Tanh-approximation GELU, defined locally so we don't depend on the exact
    // activation export name across MLX-Swift versions.
    0.5 * x * (1.0 + tanh(0.7978845608 * (x + 0.044715 * x * x * x)))
}

/// Additive causal mask: 0 on/below the diagonal, a large negative above it.
private func causalMask(_ n: Int) -> MLXArray {
    let ones = MLXArray.ones([n, n])
    return triu(ones, k: 1) * Float(-1e9)
}

final class CausalSelfAttention: Module {
    let nHeads: Int
    let headDim: Int
    let scale: Float

    @ModuleInfo var wq: Linear
    @ModuleInfo var wk: Linear
    @ModuleInfo var wv: Linear
    @ModuleInfo var wo: Linear

    // Optional LoRA adapters on the Q and V projections (the standard minimal-but-
    // effective LoRA target). nil until GPT.addLoRA(...) attaches them; frozen base
    // weights above are untouched, so the delta is purely additive.
    @ModuleInfo(key: "loraQA") var loraQA: Linear?
    @ModuleInfo(key: "loraQB") var loraQB: Linear?
    @ModuleInfo(key: "loraVA") var loraVA: Linear?
    @ModuleInfo(key: "loraVB") var loraVB: Linear?
    var loraScale: Float = 0

    init(_ c: GPTConfig) {
        self.nHeads = c.nHeads
        self.headDim = c.nEmbd / c.nHeads
        self.scale = Float(1.0 / Double(c.nEmbd / c.nHeads).squareRoot())
        self._wq.wrappedValue = Linear(c.nEmbd, c.nEmbd, bias: false)
        self._wk.wrappedValue = Linear(c.nEmbd, c.nEmbd, bias: false)
        self._wv.wrappedValue = Linear(c.nEmbd, c.nEmbd, bias: false)
        self._wo.wrappedValue = Linear(c.nEmbd, c.nEmbd, bias: false)
        super.init()
    }

    /// Attach fresh LoRA adapters (r=rank, scale=alpha/rank). B is zero-initialized
    /// so the delta is exactly zero at attachment time — training starts from the
    /// frozen base's behavior and moves away from it, not a random perturbation.
    func addLoRA(nEmbd: Int, rank: Int, alpha: Float) {
        loraQA = Linear(nEmbd, rank, bias: false)
        loraQB = Linear(rank, nEmbd, bias: false)
        loraVA = Linear(nEmbd, rank, bias: false)
        loraVB = Linear(rank, nEmbd, bias: false)
        loraQB?.update(parameters: ModuleParameters.unflattened([("weight", MLXArray.zeros(like: loraQB!.weight))]))
        loraVB?.update(parameters: ModuleParameters.unflattened([("weight", MLXArray.zeros(like: loraVB!.weight))]))
        loraScale = alpha / Float(rank)
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        let B = x.dim(0), L = x.dim(1)

        var qFull = wq(x)
        if let a = loraQA, let b = loraQB { qFull = qFull + loraScale * b(a(x)) }
        var vFull = wv(x)
        if let a = loraVA, let b = loraVB { vFull = vFull + loraScale * b(a(x)) }

        let q = qFull.reshaped([B, L, nHeads, headDim]).transposed(0, 2, 1, 3)
        let k = wk(x).reshaped([B, L, nHeads, headDim]).transposed(0, 2, 1, 3)
        let v = vFull.reshaped([B, L, nHeads, headDim]).transposed(0, 2, 1, 3)

        let out = MLXFast.scaledDotProductAttention(
            queries: q, keys: k, values: v, scale: scale, mask: mask)

        let merged = out.transposed(0, 2, 1, 3).reshaped([B, L, nHeads * headDim])
        return wo(merged)
    }
}

final class MLP: Module {
    @ModuleInfo var fc1: Linear
    @ModuleInfo var fc2: Linear

    init(_ c: GPTConfig) {
        let hidden = c.nEmbd * c.mlpRatio
        self._fc1.wrappedValue = Linear(c.nEmbd, hidden, bias: true)
        self._fc2.wrappedValue = Linear(hidden, c.nEmbd, bias: true)
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray { fc2(gelu(fc1(x))) }
}

final class Block: Module {
    @ModuleInfo var norm1: RMSNorm
    @ModuleInfo var attn: CausalSelfAttention
    @ModuleInfo var norm2: RMSNorm
    @ModuleInfo var mlp: MLP
    @ModuleInfo var drop: Dropout

    init(_ c: GPTConfig) {
        self._norm1.wrappedValue = RMSNorm(dimensions: c.nEmbd, eps: c.rmsEps)
        self._attn.wrappedValue = CausalSelfAttention(c)
        self._norm2.wrappedValue = RMSNorm(dimensions: c.nEmbd, eps: c.rmsEps)
        self._mlp.wrappedValue = MLP(c)
        self._drop.wrappedValue = Dropout(p: c.dropout)
        super.init()
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        var h = x + drop(attn(norm1(x), mask: mask))
        h = h + drop(mlp(norm2(h)))
        return h
    }
}

// MARK: - Full model

final class GPT: Module {
    let config: GPTConfig

    @ModuleInfo var tokEmb: Embedding
    @ModuleInfo var posEmb: Embedding
    @ModuleInfo var blocks: [Block]
    @ModuleInfo var normFinal: RMSNorm
    // Only allocated when weights are NOT tied. When tied, the output projection
    // reuses the token-embedding matrix via Embedding.asLinear (true weight tying —
    // one shared leaf in the parameter tree, not a copy that diverges).
    @ModuleInfo(key: "head") var head: Linear?

    init(_ c: GPTConfig) {
        self.config = c
        self._tokEmb.wrappedValue = Embedding(embeddingCount: c.vocabSize, dimensions: c.nEmbd)
        self._posEmb.wrappedValue = Embedding(embeddingCount: c.blockSize, dimensions: c.nEmbd)
        self._blocks.wrappedValue = (0 ..< c.nLayers).map { _ in Block(c) }
        self._normFinal.wrappedValue = RMSNorm(dimensions: c.nEmbd, eps: c.rmsEps)
        self._head.wrappedValue = c.tieWeights ? nil : Linear(c.nEmbd, c.vocabSize, bias: false)
        super.init()
    }

    /// idx: Int32 tensor of shape (B, L) → logits (B, L, vocab).
    func callAsFunction(_ idx: MLXArray) -> MLXArray {
        let L = idx.dim(1)
        let positions = MLXArray(0 ..< L)                        // (L,) int32
        var x = tokEmb(idx) + posEmb(positions)                  // (B, L, nEmbd)

        let mask = causalMask(L)
        for block in blocks { x = block(x, mask: mask) }

        x = normFinal(x)
        if let head { return head(x) }                           // (B, L, vocab)
        return tokEmb.asLinear(x)                                // tied projection
    }

    /// Freeze every existing parameter, then attach fresh LoRA adapters to each
    /// block's attention (Q and V projections). Call order matters: freezing before
    /// attaching means the new LoRA weights are never visited by freeze() and stay
    /// trainable, while every pretrained weight becomes frozen.
    func addLoRA(rank: Int = 8, alpha: Float = 16) {
        freeze()
        for block in blocks { block.attn.addLoRA(nEmbd: config.nEmbd, rank: rank, alpha: alpha) }
    }

    var hasLoRA: Bool { blocks.first?.attn.loraQA != nil }

    /// Parameter keys that belong to LoRA adapters (for saving a small adapter-only
    /// file separate from the full merged weights).
    static func isLoRAKey(_ key: String) -> Bool {
        key.contains("loraQA") || key.contains("loraQB") || key.contains("loraVA") || key.contains("loraVB")
    }
}

// MARK: - Loss (matches valueAndGrad(model:_:) 2-array signature)

func languageModelingLoss(model: GPT, x: MLXArray, y: MLXArray) -> MLXArray {
    maskedLanguageModelingLoss(model: model, x: x, y: y, padID: nil)
}

func maskedLanguageModelingLoss(model: GPT, x: MLXArray, y: MLXArray, padID: Int32?) -> MLXArray {
    let logits = model(x)                       // (B, L, V)
    let B = logits.dim(0), L = logits.dim(1), V = logits.dim(2)
    let flat = logits.reshaped([B * L, V])
    let targets = y.reshaped([B * L])
    let perTok = crossEntropy(logits: flat, targets: targets, reduction: .none)
    guard let padID else { return perTok.mean() }
    let wt = (targets .!= padID).asType(Float.self)
    return (perTok * wt).sum() / maximum(wt.sum(), MLXArray(Float(1e-6)))
}
