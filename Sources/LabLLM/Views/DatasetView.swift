import SwiftUI
import UniformTypeIdentifiers

struct DatasetView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var tutorial: TutorialState
    @StateObject private var browser = HFHubBrowser(kind: .corpus)
    @State private var importing = false

    var body: some View {
        VStack(spacing: 0) {
            WorkbenchPageHeader(eyebrow: "Dataset Studio", title: "Pre-Training Data", subtitle: "Browse public Hugging Face corpora and install them to disk. How much of each one a run uses is set in Training.", icon: "text.book.closed")
                .padding(.horizontal, WorkbenchTheme.pagePadding).padding(.top, 22).padding(.bottom, 14)
            GeometryReader { proxy in
                let browserWidth = min(320, max(220, proxy.size.width * 0.34))
                HStack(spacing: 0) {
                    browserPane.frame(width: browserWidth).frame(maxHeight: .infinity)
                    Divider()
                    inspectorPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if browser.results.isEmpty { browser.search() } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text, .json, .commaSeparatedText]) { result in
            if case .success(let url) = result, url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                state.loadCorpus(from: url)
                tutorial.complete(.corpusAdded)
            }
        }
        .alert("Dataset problem", isPresented: Binding(get: { state.datasetImportError != nil }, set: { if !$0 { state.datasetImportError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(state.datasetImportError ?? "") }
    }

    private var browserPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Browse pre-training data").font(.headline)
                Spacer()
                Button { importing = true } label: { Image(systemName: "folder.badge.plus") }.help("Import local text")
            }
            WorkbenchSearchBar(query: $browser.query, prompt: "Search Hugging Face") { browser.search() }
            DatasetFilterBar(browser: browser)
            if !browser.activityDetail.isEmpty {
                Text(browser.activityDetail).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            if prefs.showDatasetHints {
                Label("Starred sources are pinned first in every mode. Installed data is written to disk and stays available after a relaunch.", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if browser.isLoading && browser.visibleResults.isEmpty {
                ProgressView("Searching datasets…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DatasetResultList(browser: browser)
            }
            if let error = browser.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(16)
        .background(WorkbenchTheme.panel)
    }

    private var inspectorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let dataset = browser.selected {
                    datasetDetail(dataset)
                } else {
                    WorkbenchEmptyState(icon: "rectangle.and.text.magnifyingglass", title: "Select a dataset", message: "Search or browse the list to inspect a public dataset before installing it.")
                }
                InstalledDatasetsPanel(kind: .corpus)
            }.padding(WorkbenchTheme.pagePadding)
        }
    }

    @ViewBuilder private func datasetDetail(_ dataset: HFHubDataset) -> some View {
        VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(dataset.displayName).font(.title2.bold())
                            Text(dataset.id).font(.callout.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(prefs.mode == .simple ? "Download and install" : "Install corpus") { importSelected(dataset) }
                            .buttonStyle(WorkbenchPrimaryButtonStyle())
                            .disabled(browser.selectedFile == nil && browser.viewerSource == nil)
                            .tutorialTarget(.corpusAdded)
                    }
                    Text(dataset.summary).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        WorkbenchMetric(label: "Downloads", value: format(dataset.downloads ?? 0), icon: "arrow.down.circle")
                        WorkbenchMetric(label: "Likes", value: "\(dataset.likes ?? 0)", icon: "heart")
                        WorkbenchMetric(label: "Download", value: browser.selectedFile?.formattedSize ?? dataset.downloadSize ?? "Choose a file", icon: "arrow.down.to.line")
                    }
                    GroupBox("Import file") {
                        if browser.files.isEmpty && browser.isLoading { ProgressView("Reading repository files…") }
                        else if browser.files.isEmpty { Text("This repository has no directly importable text, JSON, JSONL, or CSV file.").foregroundStyle(.secondary) }
                        else {
                            Picker("File", selection: $browser.selectedFile) {
                                ForEach(browser.files) { file in Text(file.path).tag(Optional(file)) }
                            }.labelsHidden().frame(maxWidth: .infinity)
                        }
                    }
                    if let source = browser.viewerSource, browser.selectedFile == nil {
                        viewerImport(source)
                    }
                    GroupBox("Dataset card") {
                        if browser.isLoadingReadme { ProgressView("Loading README…") }
                        else { DatasetCardPreview(markdown: browser.readme) }
                    }
        }
    }

    private func viewerImport(_ source: HFViewerSource) -> some View {
        let maximum = max(1, source.totalRows)
        let step = maximum >= 100 ? 100 : 1
        return GroupBox("Dataset Viewer import") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hugging Face will convert this dataset's \(source.config) / \(source.split) split into training text.")
                    .font(.callout).foregroundStyle(.secondary)
                Stepper("Import \(format(browser.viewerRowLimit)) of \(format(source.totalRows)) rows", value: $browser.viewerRowLimit, in: 1...maximum, step: step)
            }
        }
    }

    private func importSelected(_ dataset: HFHubDataset) {
        if let file = browser.selectedFile { state.downloadHFCorpus(dataset, file: file) }
        else if let source = browser.viewerSource { state.importHFViewerCorpus(dataset, source: source, limit: browser.viewerRowLimit) }
        else { return }
        tutorial.complete(.corpusAdded)
    }
    private func format(_ number: Int) -> String { NumberFormatter.localizedString(from: NSNumber(value: number), number: .decimal) }
}
