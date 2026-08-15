import Foundation

/// A real, trained byte-level BPE tokenizer (GPT-2 style). Every byte maps to a
/// printable "symbol" character first (so any input is representable as a plain
/// Swift String of symbols), then merges combine frequent adjacent symbol pairs
/// into longer tokens, same idea as GPT-2/GPT-3's tokenizer.
struct BPETokenizer: Codable {
    /// token string (sequence of byte-symbols) -> id
    var vocab: [String: Int]
    /// id -> token string, for fast decode
    var idToToken: [Int: String]
    /// ordered merge rules: earlier = higher priority, applied greedily
    var merges: [[String]]

    var baseCount: Int { vocab.count }

    // MARK: - Byte <-> printable symbol mapping (GPT-2's bytes_to_unicode trick)
    // Every one of the 256 byte values gets its own single Swift Character, so a
    // sequence of bytes can be manipulated as an ordinary String during training.
    private static let byteToSymbol: [UInt8: Character] = {
        var bs: [Int] = Array(33...126) + Array(161...172) + Array(174...255)
        var cs = bs
        var n = 0
        for b in 0...255 where !bs.contains(b) {
            bs.append(b); cs.append(256 + n); n += 1
        }
        var map: [UInt8: Character] = [:]
        for (b, c) in zip(bs, cs) { map[UInt8(b)] = Character(UnicodeScalar(c)!) }
        return map
    }()
    private static let symbolToByte: [Character: UInt8] = {
        var m: [Character: UInt8] = [:]
        for (b, c) in byteToSymbol { m[c] = b }
        return m
    }()

    private static func symbols(for text: String) -> String {
        String(Array(text.utf8).map { byteToSymbol[$0]! })
    }

    // MARK: - Training

    /// Train a BPE vocabulary of `targetVocabSize` symbols from `corpus`. Calls
    /// `onProgress` periodically (0...1) so the UI can show a loading bar — training
    /// is O(merges × corpus) and can take real time on a large corpus, so callers
    /// should pass a reasonably-sized sample (a few hundred KB is plenty to learn
    /// good merges) rather than a multi-GB file.
    static func train(corpus: String, targetVocabSize: Int,
                      onProgress: ((Double) -> Void)? = nil) -> BPETokenizer {
        // Pre-tokenize into "words" on whitespace boundaries (keeps merges from
        // crossing word boundaries, same spirit as GPT-2's regex pre-tokenizer,
        // simplified to whitespace splitting for a self-contained implementation).
        let words = corpus.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        var wordSymbolSeqs: [[Character]] = words.map { Array(symbols(for: String($0))) }
        wordSymbolSeqs = wordSymbolSeqs.filter { !$0.isEmpty }
        if wordSymbolSeqs.isEmpty { wordSymbolSeqs = [Array(symbols(for: " "))] }

        var vocab: [String: Int] = [:]
        for b in 0...255 { vocab[String(byteToSymbol[UInt8(b)]!)] = vocab.count }
        var merges: [[String]] = []

        let numMerges = max(0, targetVocabSize - vocab.count)
        var wordFreq: [[Character]: Int] = [:]
        for w in wordSymbolSeqs { wordFreq[w, default: 0] += 1 }
        var words2: [([Character], Int)] = wordFreq.map { ($0.key, $0.value) }

        for step in 0 ..< numMerges {
            var pairCounts: [Pair: Int] = [:]
            for (w, freq) in words2 where w.count > 1 {
                for i in 0 ..< w.count - 1 {
                    pairCounts[Pair(String(w[i]), String(w[i + 1])), default: 0] += freq
                }
            }
            guard let best = pairCounts.max(by: { $0.value < $1.value }), best.value > 1 else { break }
            let merged = best.key.a + best.key.b
            vocab[merged] = vocab.count
            merges.append([best.key.a, best.key.b])

            words2 = words2.map { (w, freq) -> ([Character], Int) in
                var out: [Character] = []
                var i = 0
                let mergedChars = Array(merged)
                while i < w.count {
                    if i < w.count - 1, String(w[i]) == best.key.a, String(w[i + 1]) == best.key.b {
                        out.append(contentsOf: mergedChars); i += 2
                    } else {
                        out.append(w[i]); i += 1
                    }
                }
                return (out, freq)
            }

            if step % 20 == 0 { onProgress?(Double(step) / Double(max(numMerges, 1))) }
        }
        onProgress?(1.0)

        var idToToken: [Int: String] = [:]
        for (t, i) in vocab { idToToken[i] = t }
        return BPETokenizer(vocab: vocab, idToToken: idToToken, merges: merges)
    }

    private struct Pair: Hashable { let a: String; let b: String
        init(_ a: String, _ b: String) { self.a = a; self.b = b } }

    // MARK: - Encode / decode

    /// Greedy BPE encode: split into words, then repeatedly apply the
    /// highest-priority merge present, same algorithm used at training time.
    func encode(_ text: String) -> [Int32] {
        var ids: [Int32] = []
        let words = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        let rank: [Pair: Int] = {
            var r: [Pair: Int] = [:]
            for (i, m) in merges.enumerated() { r[Pair(m[0], m[1])] = i }
            return r
        }()

        for w in words where !w.isEmpty {
            var symbols = Array(Self.symbols(for: String(w))).map { String($0) }
            while symbols.count > 1 {
                var bestRank = Int.max
                var bestIdx = -1
                for i in 0 ..< symbols.count - 1 {
                    if let r = rank[Pair(symbols[i], symbols[i + 1])], r < bestRank {
                        bestRank = r; bestIdx = i
                    }
                }
                if bestIdx < 0 { break }
                let merged = symbols[bestIdx] + symbols[bestIdx + 1]
                symbols.replaceSubrange(bestIdx...bestIdx + 1, with: [merged])
            }
            for s in symbols { ids.append(Int32(vocab[s] ?? 0)) }
        }
        return ids
    }

    func decode(_ ids: [Int32]) -> String {
        var symbolString = ""
        for id in ids { symbolString += idToToken[Int(id)] ?? "" }
        let bytes = symbolString.compactMap { Self.symbolToByte[$0] }
        return String(decoding: bytes, as: UTF8.self)
    }
}
