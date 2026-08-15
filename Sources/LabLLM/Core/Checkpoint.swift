import Foundation
import MLX
import MLXNN

enum CheckpointError: LocalizedError {
    case directoryCreationFailed(String)
    case weightsWriteFailed(String)
    case weightsReadFailed(String)
    case metaMissing
    case shapeMismatch(String)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let n): return "Couldn't create a folder for checkpoint '\(n)'."
        case .weightsWriteFailed(let r): return "Couldn't write model weights: \(r)"
        case .weightsReadFailed(let r): return "Couldn't read model weights: \(r)"
        case .metaMissing: return "This checkpoint is missing its metadata file."
        case .shapeMismatch(let r): return "Checkpoint doesn't match the current model shape: \(r)"
        }
    }
}

/// Save/restore model weights (safetensors) plus a JSON sidecar (config, tokenizer,
/// training metadata) and an auto-generated Markdown model card, so a checkpoint is
/// fully reproducible and self-describing. All I/O is wrapped so failures surface as
/// readable errors instead of silently losing a training run.
enum Checkpoint {
    struct Meta: Codable {
        var config: GPTConfig
        var tokenizer: Tokenizer
        var step: Int
        var loss: Float
        var valLoss: Float
        var createdAt: Date
        var method: String = "Pretraining"     // "Pretraining", "SFT (LoRA)", "SFT (full)", "DPO"
        var datasetName: String? = nil
        var loraRank: Int? = nil               // set when this checkpoint has LoRA adapters
        var loraAlpha: Float? = nil
        var quantizedBits: Int? = nil
    }

    static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LabLLM/Checkpoints", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @discardableResult
    static func save(model: GPT, meta: Meta, name: String, hardware: HardwareInfo? = nil) throws -> URL {
        let dir = directory().appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch { throw CheckpointError.directoryCreationFailed(error.localizedDescription) }

        let flat = model.parameters().flattened()
        let weights = Dictionary(uniqueKeysWithValues: flat.map { ($0.0, $0.1) })
        do {
            try MLX.save(arrays: weights, url: dir.appendingPathComponent("model.safetensors"))
            if model.hasLoRA {
                let loraOnly = Dictionary(uniqueKeysWithValues: flat.filter { GPT.isLoRAKey($0.0) })
                try MLX.save(arrays: loraOnly, url: dir.appendingPathComponent("adapter.safetensors"))
            }
        } catch { throw CheckpointError.weightsWriteFailed(error.localizedDescription) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let metaData = try encoder.encode(meta)
            try metaData.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
        } catch { throw CheckpointError.weightsWriteFailed("metadata: \(error.localizedDescription)") }

        if let hw = hardware {
            let card = ModelCard.generate(meta: meta, hardware: hw, datasetName: meta.datasetName, method: meta.method)
            try? card.write(to: dir.appendingPathComponent("model_card.md"), atomically: true, encoding: .utf8)
        }
        return dir
    }

    static func loadMeta(from dir: URL) throws -> Meta {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")) else {
            throw CheckpointError.metaMissing
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Meta.self, from: data)
    }

    static func loadModel(from dir: URL, meta: Meta) throws -> GPT {
        let model = GPT(meta.config)
        if let rank = meta.loraRank, let alpha = meta.loraAlpha {
            model.addLoRA(rank: rank, alpha: alpha)   // matching skeleton so weights bind correctly
        }
        if let bits = meta.quantizedBits {
            quantize(model: model, groupSize: 64, bits: bits,
                     filter: { path, _ in !GPT.isLoRAKey(path) })
        }
        let weights: [String: MLXArray]
        do {
            weights = try MLX.loadArrays(url: dir.appendingPathComponent("model.safetensors"))
        } catch { throw CheckpointError.weightsReadFailed(error.localizedDescription) }
        model.update(parameters: ModuleParameters.unflattened(weights))
        eval(model)
        return model
    }

    static func list() -> [URL] {
        let dir = directory()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.hasDirectoryPath }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Among all saved checkpoints, the one with the lowest val loss (falls back to
    /// train loss if no val loss was recorded). Used to flag "best" in the browser.
    static func best() -> URL? {
        list().compactMap { url -> (URL, Float)? in
            guard let m = try? loadMeta(from: url) else { return nil }
            let score = m.valLoss > 0 ? m.valLoss : m.loss
            return (url, score)
        }.min(by: { $0.1 < $1.1 })?.0
    }

    /// Export a quantized copy of a checkpoint using MLX's native quantization
    /// (real quantized weights + scales, not a size estimate). LoRA adapter
    /// matrices are excluded — they're tiny (rank-sized) and not a meaningful
    /// target for group quantization.
    static func saveQuantized(from dir: URL, bits: Int, groupSize: Int = 64, hardware: HardwareInfo) throws
        -> (url: URL, originalBytes: Int, quantizedBytes: Int) {
        let meta = try loadMeta(from: dir)
        let model = try loadModel(from: dir, meta: meta)   // fresh instance — safe to mutate in place

        quantize(model: model, groupSize: groupSize, bits: bits,
                filter: { path, _ in !GPT.isLoRAKey(path) })

        let flat = model.parameters().flattened()
        let weights = Dictionary(uniqueKeysWithValues: flat.map { ($0.0, $0.1) })
        let outDir = directory().appendingPathComponent("\(dir.lastPathComponent)-int\(bits)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let outURL = outDir.appendingPathComponent("model.safetensors")
        do {
            try MLX.save(arrays: weights, url: outURL)
        } catch { throw CheckpointError.weightsWriteFailed(error.localizedDescription) }

        var qMeta = meta
        qMeta.method = meta.method + " · quantized \(bits)-bit"
        qMeta.createdAt = Date()
        qMeta.quantizedBits = bits
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(qMeta).write(to: outDir.appendingPathComponent("meta.json"), options: .atomic)

        let card = ModelCard.generate(meta: qMeta, hardware: hardware, datasetName: qMeta.datasetName, method: qMeta.method)
        try? card.write(to: outDir.appendingPathComponent("model_card.md"), atomically: true, encoding: .utf8)

        let origBytes = fileSize(dir.appendingPathComponent("model.safetensors"))
        let qBytes = fileSize(outURL)
        return (outDir, origBytes, qBytes)
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil ?? 0
    }
}
