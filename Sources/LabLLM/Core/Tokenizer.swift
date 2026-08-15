import Foundation

/// Character / byte tokenizers, now with a fixed block of reserved SPECIAL tokens
/// (chat role markers + end/pad/eot) that live at the top of the vocab. They're
/// reserved from the very start so a model pretrained without using them stays
/// output-compatible when you later fine-tune with them.
enum TokenizerKind: String, Codable, CaseIterable, Identifiable {
    case character
    case byte
    case bpe
    var id: String { rawValue }
    var label: String {
        switch self { case .character: return "Character"; case .byte: return "Byte-level (UTF-8)"; case .bpe: return "BPE (trained)" }
    }
}

enum Special: String, CaseIterable {
    case system = "<|system|>"
    case user = "<|user|>"
    case assistant = "<|assistant|>"
    case end = "<|end|>"
    case pad = "<|pad|>"
    case eot = "<|endoftext|>"
}

struct Tokenizer: Codable {
    var kind: TokenizerKind
    var itos: [Int: String]        // base id → character (character mode)
    var stoi: [String: Int]        // character → base id (character mode)
    var special: [String: Int]     // special-token string → id (top of vocab)
    var bpe: BPETokenizer?         // populated when kind == .bpe

    private var baseCount: Int {
        switch kind {
        case .byte: return 256
        case .character: return itos.count
        case .bpe: return bpe?.baseCount ?? 0
        }
    }
    var vocabSize: Int { baseCount + Special.allCases.count }

    // Convenience accessors
    func id(_ s: Special) -> Int32 { Int32(special[s.rawValue] ?? 0) }
    var endID: Int32 { id(.end) }
    var padID: Int32 { id(.pad) }

    static func character(from text: String) -> Tokenizer {
        let chars = Array(Set(text.map { String($0) })).sorted()
        var stoi: [String: Int] = [:]; var itos: [Int: String] = [:]
        for (i, c) in chars.enumerated() { stoi[c] = i; itos[i] = c }
        return Tokenizer(kind: .character, itos: itos, stoi: stoi, special: Self.makeSpecial(base: chars.count), bpe: nil)
    }

    static func byte() -> Tokenizer {
        Tokenizer(kind: .byte, itos: [:], stoi: [:], special: Self.makeSpecial(base: 256), bpe: nil)
    }

    /// Train a real BPE tokenizer on `text`. `targetVocabSize` includes the base
    /// byte vocab (256) plus learned merges; special tokens are reserved on top.
    static func bpeTrained(from text: String, targetVocabSize: Int,
                           onProgress: ((Double) -> Void)? = nil) -> Tokenizer {
        let trained = BPETokenizer.train(corpus: text, targetVocabSize: targetVocabSize, onProgress: onProgress)
        return Tokenizer(kind: .bpe, itos: [:], stoi: [:], special: Self.makeSpecial(base: trained.baseCount), bpe: trained)
    }

    private static func makeSpecial(base: Int) -> [String: Int] {
        var m: [String: Int] = [:]
        for (i, t) in Special.allCases.enumerated() { m[t.rawValue] = base + i }
        return m
    }

    /// Encode plain content (no special tokens). Base ids only.
    func encode(_ text: String) -> [Int32] {
        switch kind {
        case .byte:      return Array(text.utf8).map { Int32($0) }
        case .character: return text.map { Int32(stoi[String($0)] ?? 0) }
        case .bpe:       return bpe?.encode(text) ?? []
        }
    }

    /// Decode, skipping any special-token ids so displayed text stays clean.
    func decode(_ ids: [Int32]) -> String {
        let specialIDs = Set(special.values.map { Int32($0) })
        let content = ids.filter { !specialIDs.contains($0) }
        switch kind {
        case .byte:
            let bytes = content.compactMap { (0...255).contains($0) ? UInt8($0) : nil }
            return String(decoding: bytes, as: UTF8.self)
        case .character:
            return content.map { itos[Int($0)] ?? "" }.joined()
        case .bpe:
            return bpe?.decode(content) ?? ""
        }
    }
}
