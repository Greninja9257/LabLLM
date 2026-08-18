import Foundation
import Testing
@testable import LabLLM

/// The browser filters run against Hub metadata, which is inconsistent in practice:
/// tags may be missing, sizes are declared as ranges, and languages are optional.
/// These tests pin how each of those cases is treated.
struct DatasetFilterTests {
    private func dataset(id: String, title: String? = nil, downloads: Int? = nil,
                         likes: Int? = nil, rows: Int? = nil, tags: [String] = []) -> HFHubDataset {
        HFHubDataset(id: id, downloads: downloads, likes: likes, title: title, estimatedRows: rows, tags: tags)
    }

    @Test func sizeCategoryTagsParseIntoRowCounts() {
        #expect(dataset(id: "a", tags: ["size_categories:n<1K"]).approximateRows == 1_000)
        #expect(dataset(id: "b", tags: ["size_categories:1K<n<10K"]).approximateRows == 10_000)
        #expect(dataset(id: "c", tags: ["size_categories:100K<n<1M"]).approximateRows == 1_000_000)
        #expect(dataset(id: "d", tags: ["size_categories:10M<n<100M"]).approximateRows == 100_000_000)
        #expect(dataset(id: "e", tags: []).approximateRows == nil)
        // An explicit estimate always wins over the declared range.
        #expect(dataset(id: "f", rows: 2_260, tags: ["size_categories:1M<n<10M"]).approximateRows == 2_260)
    }

    @Test func sizeFilterUsesBucketsAndKeepsUnknownsOut() {
        var filters = DatasetFilters()
        filters.size = .small
        #expect(filters.matches(dataset(id: "small", tags: ["size_categories:1K<n<10K"])))
        #expect(!filters.matches(dataset(id: "big", tags: ["size_categories:10M<n<100M"])))
        // Undeclared size can't be proven to match a specific bucket.
        #expect(!filters.matches(dataset(id: "unknown")))
        #expect(DatasetFilters().matches(dataset(id: "unknown")))
    }

    @Test func categoryMatchesTagsOrRepositoryName() {
        var filters = DatasetFilters()
        filters.category = .stories
        #expect(filters.matches(dataset(id: "roneneldan/TinyStories")))
        #expect(filters.matches(dataset(id: "x/y", tags: ["fiction"])))
        #expect(!filters.matches(dataset(id: "openai/gsm8k", tags: ["math"])))

        filters.category = .math
        #expect(filters.matches(dataset(id: "openai/gsm8k", tags: ["math"])))
    }

    @Test func textFilterRequiresEveryTerm() {
        var filters = DatasetFilters()
        filters.text = "open assistant"
        #expect(filters.matches(dataset(id: "OpenAssistant/oasst1", title: "Open Assistant OASST1")))
        #expect(!filters.matches(dataset(id: "databricks/databricks-dolly-15k", title: "Dolly 15k")))
    }

    @Test func languageFilterTreatsUnlabelledDataAsEnglishAndCountsMultilingual() {
        var filters = DatasetFilters()
        filters.language = .english
        #expect(filters.matches(dataset(id: "a", tags: ["language:en"])))
        #expect(filters.matches(dataset(id: "b")))                       // unlabelled
        #expect(!filters.matches(dataset(id: "c", tags: ["language:fr"])))

        filters.language = .multilingual
        #expect(filters.matches(dataset(id: "d", tags: ["language:en", "language:fr"])))
        #expect(!filters.matches(dataset(id: "e", tags: ["language:en"])))
    }

    @Test func popularityFilterUsesDownloadCount() {
        var filters = DatasetFilters()
        filters.popularity = .tenThousand
        #expect(filters.matches(dataset(id: "a", downloads: 25_000)))
        #expect(!filters.matches(dataset(id: "b", downloads: 900)))
        #expect(!filters.matches(dataset(id: "c")))
    }

    @Test func onlySortChangesNeedNewDataFromTheHub() {
        let base = DatasetFilters()
        var narrowed = base
        narrowed.category = .code
        narrowed.text = "python"
        #expect(!narrowed.requiresRefetch(comparedTo: base))
        #expect(narrowed.activeCount == 2)

        var resorted = base
        resorted.sort = .downloads
        #expect(resorted.requiresRefetch(comparedTo: base))
        #expect(resorted.activeCount == 0)      // sorting narrows nothing
        #expect(resorted.sort.apiValue == "downloads")
        #expect(DatasetSort.relevance.apiValue == nil)
    }

    @Test func categoryChoicesAreScopedToTheBrowserKind() {
        let corpus = DatasetCategory.choices(for: .corpus)
        let fineTune = DatasetCategory.choices(for: .fineTune)
        #expect(corpus.contains(.stories))
        #expect(!corpus.contains(.preference))
        #expect(fineTune.contains(.instruction))
        #expect(!fineTune.contains(.wiki))
        #expect(corpus.first == .any && fineTune.first == .any)
    }
}

/// The Hub paginates with a cursor in the `Link` header and ignores `offset`
/// entirely, so this parsing is what makes the browser's infinite scroll advance
/// instead of re-fetching the first page forever.
struct HubPaginationTests {
    private func response(link: String?) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://huggingface.co/api/datasets")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: link.map { ["Link": $0] })!
    }

    @Test func nextCursorIsReadFromTheLinkHeader() {
        let header = "<https://huggingface.co/api/datasets?search=stories&limit=20&cursor=abc%3D%3D>; rel=\"next\""
        let next = HFHubClient.nextPageURL(from: response(link: header))
        #expect(next?.absoluteString.contains("cursor=abc") == true)
    }

    @Test func lastPageHasNoCursor() {
        #expect(HFHubClient.nextPageURL(from: response(link: nil)) == nil)
        #expect(HFHubClient.nextPageURL(from: response(link: "<https://example.com>; rel=\"prev\"")) == nil)
    }

    @Test func onlyTheNextRelationIsFollowed() {
        let header = "<https://example.com/prev>; rel=\"prev\", <https://example.com/next>; rel=\"next\""
        #expect(HFHubClient.nextPageURL(from: response(link: header))?.absoluteString == "https://example.com/next")
    }

    @Test func parquetOnlyRepositoriesCountAsImportable() {
        // They can't be downloaded as text, but the Dataset Viewer serves their rows.
        let parquet = HFHubFile(path: "data/train-00000-of-00001.parquet", size: 100)
        #expect(parquet.isParquet)
        #expect(!parquet.isFineTuneData)
        #expect(!HFHubFile(path: "README.md", size: 1).isParquet)
    }
}
