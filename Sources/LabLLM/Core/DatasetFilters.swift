import Foundation

/// What a dataset is for, derived from Hub tags and the repository name. The Hub's
/// own `task_categories` are inconsistent across repos, so the id is used as a
/// fallback signal rather than trusting tags alone.
enum DatasetCategory: String, CaseIterable, Identifiable, Codable {
    case any, stories, wiki, web, code, science, poetry, news       // corpora
    case instruction, conversation, math, qa, preference            // fine-tuning

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "Any purpose"
        case .stories: return "Stories & fiction"
        case .wiki: return "Encyclopedic"
        case .web: return "Web & general text"
        case .code: return "Code"
        case .science: return "Science & papers"
        case .poetry: return "Poetry"
        case .news: return "News"
        case .instruction: return "Instructions"
        case .conversation: return "Conversations"
        case .math: return "Math"
        case .qa: return "Question answering"
        case .preference: return "Preference pairs"
        }
    }

    /// Keywords matched against the dataset's tags and id.
    var keywords: [String] {
        switch self {
        case .any: return []
        case .stories: return ["story", "stories", "fiction", "novel", "tinystories", "book"]
        case .wiki: return ["wiki", "wikipedia", "encyclopedi"]
        case .web: return ["web", "common-crawl", "commoncrawl", "c4", "pile", "fineweb", "text-generation"]
        case .code: return ["code", "python", "programming", "github", "stack"]
        case .science: return ["arxiv", "pubmed", "science", "scientific", "paper", "abstract"]
        case .poetry: return ["poetry", "poem", "verse", "sonnet"]
        case .news: return ["news", "cnn", "bbc", "article", "headline"]
        case .instruction: return ["instruction", "alpaca", "dolly", "sft", "no_robots", "coedit"]
        case .conversation: return ["conversation", "chat", "dialog", "oasst", "ultrachat", "smoltalk"]
        case .math: return ["math", "gsm8k", "arithmetic", "reasoning"]
        case .qa: return ["qa", "squad", "question", "answer", "trivia"]
        case .preference: return ["preference", "dpo", "rlhf", "reward", "chosen"]
        }
    }

    static func choices(for kind: HFHubBrowser.Kind) -> [DatasetCategory] {
        switch kind {
        case .corpus: return [.any, .stories, .wiki, .web, .science, .poetry, .news, .code]
        case .fineTune: return [.any, .instruction, .conversation, .qa, .math, .code, .preference]
        }
    }
}

/// Row-count bucket, read from the Hub's `size_categories` tag when present and
/// from a known row estimate otherwise.
enum DatasetSize: String, CaseIterable, Identifiable, Codable {
    case any, small, medium, large

    var id: String { rawValue }
    var label: String {
        switch self {
        case .any: return "Any size"
        case .small: return "Small (< 100K rows)"
        case .medium: return "Medium (100K–10M)"
        case .large: return "Large (10M+)"
        }
    }

    /// Buckets a row count. Nil means the dataset never declared a size, which is
    /// treated as "unknown" and only excluded when a specific size is requested.
    static func bucket(forRows rows: Int) -> DatasetSize {
        switch rows {
        case ..<100_000: return .small
        case ..<10_000_000: return .medium
        default: return .large
        }
    }
}

enum DatasetLanguage: String, CaseIterable, Identifiable, Codable {
    case any, english, multilingual

    var id: String { rawValue }
    var label: String {
        switch self {
        case .any: return "Any language"
        case .english: return "English"
        case .multilingual: return "Multilingual"
        }
    }
}

enum DatasetSort: String, CaseIterable, Identifiable, Codable {
    case relevance, downloads, likes, updated

    var id: String { rawValue }
    var label: String {
        switch self {
        case .relevance: return "Best match"
        case .downloads: return "Most downloaded"
        case .likes: return "Most liked"
        case .updated: return "Recently updated"
        }
    }

    /// The Hub's `sort` query value, so ordering applies to the whole result set
    /// rather than only the pages already loaded.
    var apiValue: String? {
        switch self {
        case .relevance: return nil
        case .downloads: return "downloads"
        case .likes: return "likes"
        case .updated: return "lastModified"
        }
    }
}

enum DatasetPopularity: Int, CaseIterable, Identifiable, Codable {
    case any = 0, thousand = 1_000, tenThousand = 10_000, hundredThousand = 100_000

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .any: return "Any popularity"
        case .thousand: return "1K+ downloads"
        case .tenThousand: return "10K+ downloads"
        case .hundredThousand: return "100K+ downloads"
        }
    }
}

/// The dataset browser's filter state. Text, category, size, language and
/// popularity are applied to results already loaded; sort is sent to the Hub, so
/// changing it restarts the search.
struct DatasetFilters: Equatable {
    var text = ""
    var category: DatasetCategory = .any
    var size: DatasetSize = .any
    var language: DatasetLanguage = .any
    var popularity: DatasetPopularity = .any
    var sort: DatasetSort = .relevance

    var isDefault: Bool { self == DatasetFilters() }

    /// How many filters are narrowing the list, for the "N active" badge.
    var activeCount: Int {
        var count = 0
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { count += 1 }
        if category != .any { count += 1 }
        if size != .any { count += 1 }
        if language != .any { count += 1 }
        if popularity != .any { count += 1 }
        return count
    }

    /// Only a sort change needs new data from the Hub; everything else is applied
    /// to what is already loaded.
    func requiresRefetch(comparedTo other: DatasetFilters) -> Bool { sort != other.sort }

    func matches(_ dataset: HFHubDataset) -> Bool {
        let haystack = dataset.filterHaystack

        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if !trimmed.isEmpty {
            let terms = trimmed.split(separator: " ").map(String.init)
            guard terms.allSatisfy({ haystack.contains($0) }) else { return false }
        }

        if category != .any {
            guard category.keywords.contains(where: { haystack.contains($0) }) else { return false }
        }

        if size != .any {
            guard let rows = dataset.approximateRows, DatasetSize.bucket(forRows: rows) == size else { return false }
        }

        if language != .any {
            let languages = dataset.declaredLanguages
            switch language {
            case .english: guard languages.isEmpty || languages.contains("en") else { return false }
            case .multilingual: guard languages.count > 1 else { return false }
            case .any: break
            }
        }

        if popularity != .any {
            guard (dataset.downloads ?? 0) >= popularity.rawValue else { return false }
        }

        return true
    }
}

extension HFHubDataset {
    /// Lowercased id, title and tags, used for text and category matching.
    var filterHaystack: String {
        ([id, title ?? ""] + (tags ?? [])).joined(separator: " ").lowercased()
    }

    var declaredLanguages: [String] {
        (tags ?? []).compactMap { tag in
            guard tag.hasPrefix("language:") else { return nil }
            return String(tag.dropFirst("language:".count)).lowercased()
        }
    }

    /// Row count from the Hub's `size_categories` tag, falling back to a known
    /// estimate. The tag's upper bound is used, since that is what determines
    /// whether a dataset is a quick experiment or an overnight download.
    var approximateRows: Int? {
        if let estimatedRows { return estimatedRows }
        guard let tag = (tags ?? []).first(where: { $0.hasPrefix("size_categories:") }) else { return nil }
        let value = String(tag.dropFirst("size_categories:".count)).lowercased()
        let bounds = value.split(separator: "<").map(String.init)
        guard let upper = bounds.last else { return nil }
        return Self.rowCount(from: upper)
    }

    private static func rowCount(from token: String) -> Int? {
        let cleaned = token.replacingOccurrences(of: "n>", with: "")
            .replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let last = cleaned.last else { return nil }
        let multipliers: [Character: Int] = ["k": 1_000, "m": 1_000_000, "b": 1_000_000_000, "t": 1_000_000_000_000]
        if let multiplier = multipliers[last], let value = Int(cleaned.dropLast()) { return value * multiplier }
        return Int(cleaned)
    }
}
