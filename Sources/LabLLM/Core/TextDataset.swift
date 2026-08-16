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

    var trainWindowCount: Int { Self.validWindowCount(tokenCount: trainIds.count, blockSize: blockSize) }
    var valWindowCount: Int { Self.validWindowCount(tokenCount: valIds.count, blockSize: blockSize) }

    static func validWindowCount(tokenCount: Int, blockSize: Int) -> Int {
        max(1, tokenCount - blockSize)
    }

    func trainingWindowStarts() -> [Int] {
        Array(0 ..< trainWindowCount)
    }

    func validationWindowStarts(limit: Int? = nil) -> [Int] {
        let count = limit.map { min(max($0, 0), valWindowCount) } ?? valWindowCount
        return Array(0 ..< count)
    }

    /// Returns (x, y) each of shape (batchSize, blockSize), Int32.
    func batch(batchSize: Int, validation: Bool = false, rng: inout SeededGenerator) -> (MLXArray, MLXArray) {
        var data = validation ? valIds : trainIds
        while data.count < blockSize + 1 { data.append(tokenizer.padID) }
        let maxStart = Self.validWindowCount(tokenCount: data.count, blockSize: blockSize)

        var xs = [Int32]()
        var ys = [Int32]()
        xs.reserveCapacity(batchSize * blockSize)
        ys.reserveCapacity(batchSize * blockSize)

        for _ in 0 ..< batchSize {
            appendWindow(from: data, start: rng.nextInt(upperBound: maxStart), xs: &xs, ys: &ys)
        }

        let x = MLXArray(xs, [batchSize, blockSize])
        let y = MLXArray(ys, [batchSize, blockSize])
        return (x, y)
    }

    func fixedBatch(starts: [Int], validation: Bool = false) -> (MLXArray, MLXArray) {
        var data = validation ? valIds : trainIds
        while data.count < blockSize + 1 { data.append(tokenizer.padID) }
        let windowCount = Self.validWindowCount(tokenCount: data.count, blockSize: blockSize)
        let safeStarts = starts.isEmpty ? [0] : starts.map { min(max($0, 0), windowCount - 1) }
        var xs = [Int32]()
        var ys = [Int32]()
        xs.reserveCapacity(safeStarts.count * blockSize)
        ys.reserveCapacity(safeStarts.count * blockSize)
        for start in safeStarts { appendWindow(from: data, start: start, xs: &xs, ys: &ys) }
        return (MLXArray(xs, [safeStarts.count, blockSize]), MLXArray(ys, [safeStarts.count, blockSize]))
    }

    func fixedValidationBatches(batchSize: Int, maxBatches: Int = 5) -> [(MLXArray, MLXArray)] {
        let count = min(valWindowCount, max(batchSize, 1) * max(maxBatches, 1))
        let starts = validationWindowStarts(limit: count)
        let chunkSize = max(batchSize, 1)
        return stride(from: 0, to: starts.count, by: chunkSize).map { offset in
            let chunk = Array(starts[offset ..< min(offset + chunkSize, starts.count)])
            return fixedBatch(starts: chunk, validation: true)
        }
    }

    private func appendWindow(from data: [Int32], start: Int, xs: inout [Int32], ys: inout [Int32]) {
        xs.append(contentsOf: data[start ..< start + blockSize])
        ys.append(contentsOf: data[start + 1 ..< start + blockSize + 1])
    }
}
