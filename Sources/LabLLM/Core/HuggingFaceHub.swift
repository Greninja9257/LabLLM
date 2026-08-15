import Foundation

indirect enum HFJSONValue: Decodable, Sendable {
    case string(String), number(Double), bool(Bool), array([HFJSONValue]), object([String: HFJSONValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([HFJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: HFJSONValue].self)) }
    }

    var foundationValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .array(let values): return values.map(\.foundationValue)
        case .object(let values): return values.mapValues(\.foundationValue)
        case .null: return NSNull()
        }
    }

    var text: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

struct HFViewerSource: Hashable, Sendable {
    let config: String
    let split: String
    let totalRows: Int
}

private struct HFViewerSplitResponse: Decodable {
    struct Split: Decodable { let config: String; let split: String }
    let splits: [Split]
}

private struct HFViewerRowsResponse: Decodable {
    struct Row: Decodable { let row: [String: HFJSONValue] }
    let rows: [Row]
    let num_rows_total: Int?
}

struct HFHubDataset: Identifiable, Decodable, Hashable, Sendable {
    let id: String
    let author: String?
    let lastModified: String?
    let downloads: Int?
    let likes: Int?
    let tags: [String]?
    let title: String?
    let downloadSize: String?
    let estimatedRows: Int?
    let preferredFileContains: String?

    init(id: String, author: String? = nil, lastModified: String? = nil, downloads: Int? = nil, likes: Int? = nil, title: String? = nil, downloadSize: String? = nil, estimatedRows: Int? = nil, tags: [String]? = nil, preferredFileContains: String? = nil) {
        self.id = id; self.author = author; self.lastModified = lastModified; self.downloads = downloads
        self.likes = likes; self.tags = tags; self.title = title; self.downloadSize = downloadSize; self.estimatedRows = estimatedRows; self.preferredFileContains = preferredFileContains
    }

    var displayName: String { title ?? id.split(separator: "/").last.map(String.init) ?? id }
    var summary: String {
        let task = tags?.first(where: { $0.hasPrefix("task_categories:") })?.replacingOccurrences(of: "task_categories:", with: "")
        return task?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Public Hugging Face dataset"
    }
    var license: String { "See dataset card" }
}

struct HFHubFile: Identifiable, Decodable, Hashable, Sendable {
    let path: String
    let size: Int?
    var id: String { path }
    private var lowerPath: String { path.lowercased() }
    var isTextLike: Bool {
        lowerPath.hasSuffix(".txt") || lowerPath.hasSuffix(".text") || lowerPath.hasSuffix(".jsonl") || lowerPath.hasSuffix(".json") || lowerPath.hasSuffix(".csv")
    }
    var isJSONL: Bool { lowerPath.hasSuffix(".jsonl") }
    var isFineTuneData: Bool { isJSONL || lowerPath.hasSuffix(".json") }
    var formattedSize: String? { size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } }
}

struct CorpusSource: Identifiable {
    let id = UUID()
    let name: String
    let origin: String
    let text: String
    var isEnabled = true
    var percent: Double = 100
    var selectedText: String {
        let count = max(1, Int((Double(text.count) * percent / 100).rounded()))
        return String(text.prefix(count))
    }
}

@MainActor
final class HFHubBrowser: ObservableObject {
    @Published var query = ""
    @Published var results: [HFHubDataset] = []
    @Published var selected: HFHubDataset?
    @Published var files: [HFHubFile] = []
    @Published var selectedFile: HFHubFile?
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var readme = ""
    @Published var isLoadingReadme = false
    @Published var error: String?
    @Published var activityDetail = ""
    @Published var viewerSource: HFViewerSource?
    @Published var viewerRowLimit = 10_000

    let kind: Kind
    private var offset = 0
    private let pageSize = 15
    private var hasMore = true
    private var searchGeneration = UUID()
    enum Kind { case corpus, fineTune }

    init(kind: Kind) { self.kind = kind }

    var pinned: [HFHubDataset] {
        switch kind {
        case .corpus:
            return [
                .init(id: "roneneldan/TinyStories", title: "TinyStories 2", downloadSize: "2.24 GB", tags: ["text-generation"], preferredFileContains: "TinyStoriesV2-GPT4-train.txt"),
                .init(id: "roneneldan/TinyStories", title: "TinyStories", downloadSize: "1.92 GB", tags: ["text-generation"], preferredFileContains: "TinyStories-train.txt"),
                .init(id: "Salesforce/wikitext", title: "WikiText-2 Raw", downloadSize: "4.7 MB", tags: ["text-generation"]),
                .init(id: "wikimedia/wikipedia", title: "Simple English Encyclopedia", downloadSize: "~300 MB", tags: ["text-generation"]),
                .init(id: "wikimedia/wikipedia", title: "GoodWiki", downloadSize: "Varies by snapshot", tags: ["text-generation"]),
                .init(id: "karpathy/tiny_shakespeare", title: "Tiny Shakespeare", downloadSize: "1.1 MB", tags: ["text-generation"]),
                .init(id: "ccdv/arxiv-summarization", title: "arXiv Abstracts", downloadSize: "~240 MB", tags: ["text-generation"]),
                .init(id: "DanFosing/public-domain-poetry", title: "Public Domain Poetry", downloadSize: "94.2 MB", tags: ["text-generation"]),
            ]
        case .fineTune:
            return [
                .init(id: "HuggingFaceTB/everyday-conversations-llama3.1-2k", title: "Everyday Conversations 2k", estimatedRows: 2_260, tags: ["conversation"]),
                .init(id: "HuggingFaceH4/no_robots", title: "No Robots", estimatedRows: 10_000, tags: ["instruction"]),
                .init(id: "databricks/databricks-dolly-15k", title: "Dolly 15k", estimatedRows: 15_011, tags: ["instruction"]),
                .init(id: "OpenAssistant/oasst1", title: "Open Assistant OASST1", estimatedRows: 161_443, tags: ["conversation"]),
                .init(id: "HuggingFaceTB/smoltalk", title: "SmolTalk", estimatedRows: 1_000_000, tags: ["conversation"]),
                .init(id: "openai/gsm8k", title: "GSM8K", estimatedRows: 8_792, tags: ["instruction", "math"]),
                .init(id: "grammarly/coedit", title: "CoEdIT", estimatedRows: 82_000, tags: ["instruction"]),
                .init(id: "sahil2801/CodeAlpaca-20k", title: "CodeAlpaca 20k", estimatedRows: 20_022, tags: ["instruction", "code"]),
                .init(id: "rajpurkar/squad", title: "SQuAD", estimatedRows: 87_599, tags: ["instruction"]),
                .init(id: "HuggingFaceH4/ultrachat_200k", title: "UltraChat 200k", estimatedRows: 207_865, tags: ["conversation"]),
            ]
        }
    }

    func search(reset: Bool = true) {
        if reset {
            searchGeneration = UUID()
            offset = 0; hasMore = true; results = []; selected = nil; files = []; selectedFile = nil; viewerSource = nil
            activityDetail = "Searching in \(pageSize)-result batches…"
        } else if isLoading || isLoadingMore { return }
        guard hasMore else { return }
        if reset { isLoading = true } else { isLoadingMore = true }
        let enteredQuery = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let browserKind = kind
        let query = enteredQuery.isEmpty ? (browserKind == .corpus ? "text generation" : "instruction") : enteredQuery
        let currentOffset = offset
        let pageSize = self.pageSize
        let generation = searchGeneration
        Task {
            defer {
                if self.searchGeneration == generation {
                    self.isLoading = false; self.isLoadingMore = false
                }
            }
            do {
                let page = try await Task.detached { try await HFHubClient.search(query: query, limit: pageSize, offset: currentOffset) }.value
                let candidates = page.filter { Self.matches($0, kind: browserKind) }
                let importable = await Task.detached { await HFHubClient.importableDatasets(candidates, kind: browserKind) }.value
                guard self.searchGeneration == generation else { return }
                results.append(contentsOf: importable.filter { !results.contains($0) })
                offset += page.count
                hasMore = page.count == pageSize
                activityDetail = hasMore ? "Loaded \(results.count) importable results. Scroll for the next batch." : "Loaded \(results.count) importable results."
            } catch where self.searchGeneration == generation { self.error = error.localizedDescription }
        }
    }

    func loadMoreIfNeeded(_ item: HFHubDataset) { if item == results.last { search(reset: false) } }

    func select(_ dataset: HFHubDataset?) {
        selected = dataset; files = []; selectedFile = nil; viewerSource = nil; readme = ""
        guard let dataset else { return }
        isLoading = true
        isLoadingReadme = true
        activityDetail = "Inspecting repository files in small batches…"
        let browserKind = kind
        Task {
            defer { isLoading = false }
            do {
                let loaded = try await Task.detached { try await HFHubClient.compatibleFiles(repo: dataset.id, kind: browserKind, limit: 250) }.value
                files = loaded
                let preferred = dataset.preferredFileContains.flatMap { match in files.first { $0.path.localizedCaseInsensitiveContains(match) } }
                selectedFile = preferred ?? (browserKind == .fineTune ? files.first(where: \.isJSONL) ?? files.first : files.first(where: { !$0.isJSONL }) ?? files.first)
                activityDetail = "Found \(files.count) importable file\(files.count == 1 ? "" : "s")."
            } catch { self.error = error.localizedDescription }
        }
        Task {
            do {
                let source = try await Task.detached { try await HFHubClient.viewerSource(repo: dataset.id) }.value
                guard self.selected == dataset else { return }
                viewerSource = source
                if let source { viewerRowLimit = min(max(1, viewerRowLimit), source.totalRows) }
            } catch {
                // A raw compatible file remains usable when the Dataset Viewer is unavailable.
            }
        }
        Task {
            defer { isLoadingReadme = false }
            readme = (try? await Task.detached { try await HFHubClient.readme(repo: dataset.id) }.value) ?? "No README was published for this dataset."
        }
    }

    private static func matches(_ dataset: HFHubDataset, kind: Kind) -> Bool {
        let text = ([dataset.id] + (dataset.tags ?? [])).joined(separator: " ").lowercased()
        switch kind {
        case .fineTune:
            return text.contains("instruction") || text.contains("conversation") || text.contains("chat") || text.contains("sft") || text.contains("alpaca") || text.contains("preference") || text.contains("qa")
        case .corpus:
            return !text.contains("preference") && !text.contains("rlhf") && !text.contains("reward")
        }
    }
}

enum HFHubClient {
    static func search(query: String, limit: Int, offset: Int) async throws -> [HFHubDataset] {
        var components = URLComponents(string: "https://huggingface.co/api/datasets")!
        components.queryItems = [URLQueryItem(name: "search", value: query), URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "full", value: "true")]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw ConversationImportError.network("Couldn't search Hugging Face datasets.") }
        return try JSONDecoder().decode([HFHubDataset].self, from: data)
    }

    static func files(repo: String, path: String? = nil, recursive: Bool = true) async throws -> [HFHubFile] {
        let encoded = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        let suffix = path.map { "/\($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0)" } ?? ""
        let recursiveQuery = recursive ? "&recursive=true" : ""
        let url = URL(string: "https://huggingface.co/api/datasets/\(encoded)/tree/main\(suffix)?expand=true\(recursiveQuery)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw ConversationImportError.network("Couldn't read the files for \(repo).") }
        return try JSONDecoder().decode([HFHubFile].self, from: data)
    }

    static func compatibleFiles(repo: String, kind: HFHubBrowser.Kind, limit: Int) async throws -> [HFHubFile] {
        let compatible: (HFHubFile) -> Bool = { kind == .fineTune ? $0.isFineTuneData : $0.isTextLike }
        var found: [HFHubFile] = []
        let root = try await files(repo: repo, recursive: false)
        found.append(contentsOf: root.filter(compatible))
        if found.count >= limit { return Array(found.prefix(limit)) }

        let folders = ["data", "train", "dataset", "default", "raw"]
        for folder in folders where root.contains(where: { $0.path == folder }) {
            let nested = (try? await files(repo: repo, path: folder, recursive: true)) ?? []
            found.append(contentsOf: nested.filter(compatible))
            if found.count >= limit { break }
        }
        return Array(found.prefix(limit))
    }

    static func importableDatasets(_ candidates: [HFHubDataset], kind: HFHubBrowser.Kind) async -> [HFHubDataset] {
        await withTaskGroup(of: HFHubDataset?.self) { group in
            for dataset in candidates {
                group.addTask {
                    guard let root = try? await files(repo: dataset.id, recursive: false) else { return nil }
                    let compatible: (HFHubFile) -> Bool = { kind == .fineTune ? $0.isFineTuneData : $0.isTextLike }
                    if root.contains(where: compatible) { return dataset }
                    for directory in ["data", "train", "dataset", "default", "raw"] where root.contains(where: { $0.path == directory }) {
                        if let nested = try? await files(repo: dataset.id, path: directory, recursive: false), nested.contains(where: compatible) { return dataset }
                    }
                    return nil
                }
            }
            var verified: [HFHubDataset] = []
            for await result in group { if let result { verified.append(result) } }
            return verified
        }
    }

    static func readme(repo: String) async throws -> String {
        guard let url = HFDownloader.url(repo: repo, filePath: "README.md") else { throw ConversationImportError.network("Invalid dataset repository.") }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let text = String(data: data, encoding: .utf8) else { throw ConversationImportError.network("Couldn't load the dataset README.") }
        return text
    }

    static func viewerSource(repo: String) async throws -> HFViewerSource? {
        let splits = try await viewerRequest(path: "splits", query: ["dataset": repo], as: HFViewerSplitResponse.self).splits
        guard let split = splits.sorted(by: { lhs, rhs in
            let lhsPriority = lhs.split == "train" ? 0 : lhs.split == "validation" ? 1 : 2
            let rhsPriority = rhs.split == "train" ? 0 : rhs.split == "validation" ? 1 : 2
            return lhsPriority == rhsPriority ? lhs.config < rhs.config : lhsPriority < rhsPriority
        }).first else { return nil }
        let page = try await viewerPage(repo: repo, config: split.config, split: split.split, offset: 0, length: 1)
        guard page.totalRows > 0 else { return nil }
        return HFViewerSource(config: split.config, split: split.split, totalRows: page.totalRows)
    }

    static func viewerRows(repo: String, source: HFViewerSource, limit: Int, progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> [[String: HFJSONValue]] {
        let target = min(max(1, limit), source.totalRows)
        var rows: [[String: HFJSONValue]] = []
        var offset = 0
        while offset < target {
            try Task.checkCancellation()
            let page = try await viewerPage(repo: repo, config: source.config, split: source.split, offset: offset, length: min(100, target - offset))
            guard !page.rows.isEmpty else { break }
            rows.append(contentsOf: page.rows)
            offset += page.rows.count
            progress(rows.count, target)
        }
        return rows
    }

    private static func viewerPage(repo: String, config: String, split: String, offset: Int, length: Int) async throws -> (rows: [[String: HFJSONValue]], totalRows: Int) {
        let response = try await viewerRequest(path: "rows", query: [
            "dataset": repo, "config": config, "split": split,
            "offset": String(offset), "length": String(length)
        ], as: HFViewerRowsResponse.self)
        return (response.rows.map(\.row), response.num_rows_total ?? 0)
    }

    private static func viewerRequest<T: Decodable>(path: String, query: [String: String], as type: T.Type) async throws -> T {
        var components = URLComponents(string: "https://datasets-server.huggingface.co/\(path)")!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ConversationImportError.network("Hugging Face Dataset Viewer couldn't read this dataset.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
