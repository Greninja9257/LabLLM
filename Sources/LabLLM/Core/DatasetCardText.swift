import Foundation

/// Turns a Hugging Face dataset README into displayable blocks.
///
/// Real dataset cards are not clean Markdown: they open with a YAML frontmatter
/// block, and the body is frequently HTML — `<div align="center">`, `<img>`
/// banners, `<a>` badges, `<br>`, `<li>`, tables, and HTML entities. Rendering
/// them raw showed the markup as literal text, so the card is normalized to plain
/// text first and then split into blocks the preview can style.
enum DatasetCardText {
    enum Block: Identifiable, Equatable {
        case heading(level: Int, text: String)
        case bullet(String)
        case quote(String)
        case code(String)
        case table(String)
        case rule
        case paragraph(String)

        var id: String {
            switch self {
            case .heading(let level, let text): return "h\(level):\(text)"
            case .bullet(let text): return "b:\(text)"
            case .quote(let text): return "q:\(text)"
            case .code(let text): return "c:\(text)"
            case .table(let text): return "t:\(text)"
            case .rule: return "rule"
            case .paragraph(let text): return "p:\(text)"
            }
        }
    }

    /// Full pipeline: drop frontmatter, flatten HTML, then classify each line.
    static func blocks(from raw: String) -> [Block] {
        let text = plainText(from: raw)
        var blocks: [Block] = []
        var codeBuffer: [String] = []
        var inCodeFence = false

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCodeFence {
                    blocks.append(.code(codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll()
                }
                inCodeFence.toggle()
                continue
            }
            if inCodeFence { codeBuffer.append(rawLine); continue }
            guard !line.isEmpty else { continue }

            if line.hasPrefix("######") { blocks.append(.heading(level: 4, text: heading(line, hashes: 6))) }
            else if line.hasPrefix("#####") { blocks.append(.heading(level: 4, text: heading(line, hashes: 5))) }
            else if line.hasPrefix("####") { blocks.append(.heading(level: 4, text: heading(line, hashes: 4))) }
            else if line.hasPrefix("###") { blocks.append(.heading(level: 3, text: heading(line, hashes: 3))) }
            else if line.hasPrefix("##") { blocks.append(.heading(level: 2, text: heading(line, hashes: 2))) }
            else if line.hasPrefix("#") { blocks.append(.heading(level: 1, text: heading(line, hashes: 1))) }
            else if line == "---" || line == "***" || line == "___" { blocks.append(.rule) }
            else if line.hasPrefix("> ") { blocks.append(.quote(String(line.dropFirst(2)))) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                blocks.append(.bullet(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            }
            else if line.hasPrefix("|") { blocks.append(.table(line)) }
            else { blocks.append(.paragraph(line)) }
        }
        if !codeBuffer.isEmpty { blocks.append(.code(codeBuffer.joined(separator: "\n"))) }
        return blocks
    }

    private static func heading(_ line: String, hashes: Int) -> String {
        String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
    }

    /// Strips YAML frontmatter and flattens HTML into readable text.
    static func plainText(from raw: String) -> String {
        var text = stripFrontmatter(raw)
        text = stripElements(named: ["script", "style", "head"], in: text)
        text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        text = convertStructuralTags(in: text)
        text = convertImages(in: text)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(in: text)
        return collapseBlankLines(in: text)
    }

    /// Dataset cards start with a `---` delimited YAML block of tags, licenses and
    /// config metadata. It is machine data, not part of the card's prose.
    static func stripFrontmatter(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return raw }
        var lines = trimmed.components(separatedBy: "\n")
        lines.removeFirst()
        guard let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return raw }
        return lines[lines.index(after: end)...].joined(separator: "\n")
    }

    private static func stripElements(named names: [String], in text: String) -> String {
        names.reduce(text) { partial, name in
            partial.replacingOccurrences(of: "<\(name)[\\s\\S]*?</\(name)>",
                                         with: "",
                                         options: [.regularExpression, .caseInsensitive])
        }
    }

    /// Line breaks, list items and HTML headings carry structure that would be lost
    /// if every tag were simply deleted, so they are translated before tag removal.
    private static func convertStructuralTags(in text: String) -> String {
        var out = text
        let newlineTags = ["</p>", "<p>", "<br>", "<br/>", "<br />", "</div>", "</tr>", "</ul>", "<ul>",
                           "</ol>", "<ol>", "</table>", "</blockquote>", "<blockquote>", "</section>"]
        for tag in newlineTags {
            out = out.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        out = out.replacingOccurrences(of: "<li[^>]*>", with: "\n- ", options: [.regularExpression, .caseInsensitive])
        out = out.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
        for level in 1...6 {
            out = out.replacingOccurrences(of: "<h\(level)[^>]*>",
                                           with: "\n" + String(repeating: "#", count: level) + " ",
                                           options: [.regularExpression, .caseInsensitive])
            out = out.replacingOccurrences(of: "</h\(level)>", with: "\n", options: .caseInsensitive)
        }
        out = out.replacingOccurrences(of: "</t[dh]>", with: " ", options: [.regularExpression, .caseInsensitive])
        return out
    }

    /// Banner images can't be fetched offline, so keep their alt text (which is
    /// usually the dataset name or badge label) and drop the rest.
    private static func convertImages(in text: String) -> String {
        var out = text
        // Markdown images first, then HTML ones, keeping alt text where present.
        out = out.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        let pattern = "<img[^>]*?alt=[\"']([^\"']*)[\"'][^>]*>"
        out = out.replacingOccurrences(of: pattern, with: "$1", options: [.regularExpression, .caseInsensitive])
        out = out.replacingOccurrences(of: "<img[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        return out
    }

    private static func decodeEntities(in text: String) -> String {
        var out = text
        let named: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&#39;": "'", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
            "&copy;": "©", "&reg;": "®", "&trade;": "™", "&rarr;": "→", "&larr;": "←", "&bull;": "•"
        ]
        for (entity, replacement) in named {
            out = out.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        // Remaining numeric entities (&#8212; and &#x2014; forms).
        out = replaceNumericEntities(in: out)
        return out
    }

    private static func replaceNumericEntities(in text: String) -> String {
        guard text.contains("&#") else { return text }
        var result = ""
        var remainder = Substring(text)
        while let start = remainder.range(of: "&#") {
            result += remainder[remainder.startIndex..<start.lowerBound]
            let afterMarker = remainder[start.upperBound...]
            guard let end = afterMarker.firstIndex(of: ";") else {
                result += remainder[start.lowerBound...]
                return result
            }
            let digits = afterMarker[afterMarker.startIndex..<end]
            let isHex = digits.first == "x" || digits.first == "X"
            let value = isHex ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
            if let value, let scalar = Unicode.Scalar(value) {
                result.append(Character(scalar))
            } else {
                result += "&#" + digits + ";"
            }
            remainder = afterMarker[afterMarker.index(after: end)...]
        }
        result += remainder
        return result
    }

    private static func collapseBlankLines(in text: String) -> String {
        text.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
