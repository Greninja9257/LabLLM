import Foundation
import MLX

/// Loads a plain-text corpus, encodes it once with the tokenizer, holds a
/// train/val split as flat Int32 arrays, and hands out random contiguous
/// batches for next-token prediction.
final class TextDataset {
    let tokenizer: Tokenizer
    let blockSize: Int
    private let trainIds: [Int32]
    private let valIds: [Int32]

    var totalTokens: Int { trainIds.count + valIds.count }
    var trainTokens: Int { trainIds.count }
    var valTokens: Int { valIds.count }

    init(text: String, tokenizer: Tokenizer, blockSize: Int, valFraction: Double = 0.1) {
        self.tokenizer = tokenizer
        self.blockSize = blockSize
        var ids = tokenizer.encode(text)
        if ids.isEmpty { ids = [tokenizer.padID] }
        while ids.count < blockSize + 1 { ids.append(tokenizer.padID) }

        let split = min(max(Int(Double(ids.count) * (1.0 - valFraction)), blockSize + 1), ids.count)
        self.trainIds = Array(ids[..<split])

        let valStart = min(max(split, 0), max(0, ids.count - (blockSize + 1)))
        self.valIds = Array(ids[valStart...])
    }

    /// Returns (x, y) each of shape (batchSize, blockSize), Int32.
    func batch(batchSize: Int, validation: Bool = false) -> (MLXArray, MLXArray) {
        var data = validation ? valIds : trainIds
        while data.count < blockSize + 1 { data.append(tokenizer.padID) }
        let maxStart = max(1, data.count - blockSize - 1)

        var xs = [Int32]()
        var ys = [Int32]()
        xs.reserveCapacity(batchSize * blockSize)
        ys.reserveCapacity(batchSize * blockSize)

        for _ in 0 ..< batchSize {
            let start = Int.random(in: 0 ..< maxStart)
            xs.append(contentsOf: data[start ..< start + blockSize])
            ys.append(contentsOf: data[start + 1 ..< start + blockSize + 1])
        }

        let x = MLXArray(xs, [batchSize, blockSize])
        let y = MLXArray(ys, [batchSize, blockSize])
        return (x, y)
    }
}
