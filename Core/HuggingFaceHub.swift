import Foundation

struct HFHubDataset: Identifiable, Decodable, Hashable {
    let id: String
    let author: String?
    let lastModified: String?
    let downloads: Int?
    let likes: Int?
    let tags: [String]?
    let cardData: HFCardData?

    struct HFCardData: Decodable, Hashable {
        let license: String?
        let language: [String]?
        let sizeCategories: [String]?
    }

    var displayName: String { id.split(separator: "/").last.map(String.init) ?? id }
    var summary: String {
        let task = tags?.first(where: { $0.hasPrefix("task_categories:") })?.replacingOccurrences(of: "task_categories:", with: "")
        return task?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Public Hugging Face dataset"
    }
    var license: String { cardData?.license ?? "License not declared" }
}

struct HFHubFile: Identifiable, Decodable, Hashable {
    let path: String
    let type: String?
    let size: Int?
    var id: String { path }
    var isTextLike: Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".txt") || lower.hasSuffix(".text") || lower.hasSuffix(".md") || lower.hasSuffix(".jsonl") || lower.hasSuffix(".json")
    }
    var isJSONL: Bool { path.lowercased().hasSuffix(".jsonl") }
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
    @Published var error: String?

    let kind: Kind
    private var offset = 0
    private let pageSize = 30
    private var hasMore = true

    enum Kind { case corpus, fineTune }

    init(kind: Kind) { self.kind = kind }

    func search(reset: Bool = true) {
        guard !isLoading, !isLoadingMore else { return }
        if reset { offset = 0; hasMore = true; results = []; selected = nil; files = []; selectedFile = nil }
        guard hasMore else { return }
        if reset { isLoading = true } else { isLoadingMore = true }
        let query = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentOffset = offset
        Task {
            defer { self.isLoading = false; self.isLoadingMore = false }
            do {
                let page = try await HFHubClient.search(query: query, limit: pageSize, offset: currentOffset)
                let filtered = self.kind == .fineTune ? page.filter { Self.likelyFineTune($0) } : page
                self.results.append(contentsOf: filtered.filter { !self.results.contains($0) })
                self.offset += page.count
                self.hasMore = page.count == self.pageSize
                if self.selected == nil { self.select(self.results.first) }
            } catch { self.error = error.localizedDescription }
        }
    }

    func loadMoreIfNeeded(_ item: HFHubDataset) {
        if item == results.last { search(reset: false) }
    }

    func select(_ dataset: HFHubDataset?) {
        selected = dataset; files = []; selectedFile = nil
        guard let dataset else { return }
        isLoading = true
        Task {
            defer { self.isLoading = false }
            do {
                let loaded = try await HFHubClient.files(repo: dataset.id)
                self.files = loaded.filter(\.isTextLike)
                self.selectedFile = self.kind == .fineTune ? self.files.first(where: \.isJSONL) : self.files.first(where: { !$0.isJSONL }) ?? self.files.first
            } catch { self.error = error.localizedDescription }
        }
    }

    private static func likelyFineTune(_ dataset: HFHubDataset) -> Bool {
        let text = ([dataset.id] + (dataset.tags ?? [])).joined(separator: " ").lowercased()
        return text.contains("instruction") || text.contains("conversation") || text.contains("chat") || text.contains("sft") || text.contains("alpaca") || text.contains("preference")
    }
}

enum HFHubClient {
    static func search(query: String, limit: Int, offset: Int) async throws -> [HFHubDataset] {
        var components = URLComponents(string: "https://huggingface.co/api/datasets")!
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "full", value: "true")
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw ConversationImportError.network("Couldn't search Hugging Face datasets.") }
        return try JSONDecoder().decode([HFHubDataset].self, from: data)
    }

    static func files(repo: String) async throws -> [HFHubFile] {
        let encoded = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        let url = URL(string: "https://huggingface.co/api/datasets/\(encoded)/tree/main?recursive=true&expand=true")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw ConversationImportError.network("Couldn't read the files for \(repo).") }
        return try JSONDecoder().decode([HFHubFile].self, from: data)
    }
}
