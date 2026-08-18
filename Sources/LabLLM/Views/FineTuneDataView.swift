import SwiftUI
import UniformTypeIdentifiers

struct FineTuneDataView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var tutorial: TutorialState
    @StateObject private var browser = HFHubBrowser(kind: .fineTune)
    @State private var importingSFT = false
    @State private var importingIMessage = false

    /// Recommended sources stay pinned to the top in every mode. They are the
    /// repositories known to import cleanly here, which is just as useful to an
    /// expert as to a beginner.
    private var displayedResults: [HFHubDataset] {
        let remote = browser.results.filter { remote in !browser.pinned.contains(where: { $0.id == remote.id }) }
        return browser.pinned + remote.sorted { ($0.downloads ?? 0) > ($1.downloads ?? 0) }
    }

    private func isRecommended(_ dataset: HFHubDataset) -> Bool {
        browser.pinned.contains { $0.displayName == dataset.displayName && $0.id == dataset.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkbenchPageHeader(eyebrow: "Dataset Studio", title: "Fine-tuning Data", subtitle: "Find compatible instruction datasets and install them to disk. The SFT mix itself is composed in Training.", icon: "tray.full")
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
        .fileImporter(isPresented: $importingSFT, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result, url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                state.importLocalJSONL(url: url)
                tutorial.complete(.fineTuneSourceAdded)
            }
        }
        .fileImporter(isPresented: $importingIMessage, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result, url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                state.importIMessageDatabase(url: url)
                tutorial.complete(.fineTuneSourceAdded)
            }
        }
        .alert("Dataset problem", isPresented: Binding(get: { state.datasetImportError != nil }, set: { if !$0 { state.datasetImportError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(state.datasetImportError ?? "") }
    }

    private var browserPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Browse fine-tuning data").font(.headline)
                Spacer()
                Button { importingIMessage = true } label: { Image(systemName: "message.badge") }.help("Import iMessage chat.db")
                Button { importingSFT = true } label: { Image(systemName: "folder.badge.plus") }.help("Import local JSONL")
            }
            WorkbenchSearchBar(query: $browser.query, prompt: "Search Hugging Face") { browser.search() }
            if !browser.activityDetail.isEmpty {
                Text(browser.activityDetail).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            if prefs.showDatasetHints {
                Label("Starred sources are pinned first in every mode. Results prioritize importable instruction and conversation data, including Parquet-backed datasets.", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if browser.isLoading && browser.results.isEmpty { ProgressView("Searching datasets…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(displayedResults) { dataset in
                            FineTuneBrowserRow(dataset: dataset, isSelected: browser.selected == dataset, recommended: isRecommended(dataset))
                                .contentShape(Rectangle())
                                .onTapGesture { browser.select(dataset) }
                                .onAppear { browser.loadMoreIfNeeded(dataset) }
                        }
                        if browser.isLoadingMore { ProgressView().padding() }
                    }
                }
            }
            if let error = browser.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(16).background(WorkbenchTheme.panel)
    }

    private var inspectorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let dataset = browser.selected {
                    datasetDetail(dataset)
                } else {
                    WorkbenchEmptyState(icon: "rectangle.and.text.magnifyingglass", title: "Select a dataset", message: "Inspect a compatible JSONL dataset before installing it.")
                }
                InstalledDatasetsPanel(kind: .fineTune)
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
                        Button(prefs.mode == .simple ? "Download and install" : "Install dataset") { importSelected(dataset) }
                            .buttonStyle(WorkbenchPrimaryButtonStyle())
                            .disabled(browser.selectedFile == nil && browser.viewerSource == nil)
                            .tutorialTarget(.fineTuneSourceAdded)
                    }
                    Text(dataset.summary).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        WorkbenchMetric(label: "Downloads", value: format(dataset.downloads ?? 0), icon: "arrow.down.circle")
                        WorkbenchMetric(label: "Likes", value: "\(dataset.likes ?? 0)", icon: "heart")
                        WorkbenchMetric(label: "Rows", value: format(dataset.estimatedRows ?? 0), icon: "number")
                    }
                    GroupBox("Compatible file") {
                        if browser.files.isEmpty && browser.isLoading { ProgressView("Reading repository files…") }
                        else if browser.files.filter(\.isFineTuneData).isEmpty { Text("No compatible JSON or JSONL file was found in this repository. Choose a different dataset or import a local JSONL file.").foregroundStyle(.secondary) }
                        else {
                            Picker("Data file", selection: $browser.selectedFile) {
                                ForEach(browser.files.filter(\.isFineTuneData)) { file in Text(file.path).tag(Optional(file)) }
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
                Text("Hugging Face will convert \(source.config) / \(source.split) into recognized chat or instruction rows.")
                    .font(.callout).foregroundStyle(.secondary)
                Stepper("Import \(format(browser.viewerRowLimit)) of \(format(source.totalRows)) rows", value: $browser.viewerRowLimit, in: 1...maximum, step: step)
            }
        }
    }

    private func importSelected(_ dataset: HFHubDataset) {
        if let file = browser.selectedFile { state.downloadHFDataset(dataset, file: file) }
        else if let source = browser.viewerSource { state.importHFViewerDataset(dataset, source: source, limit: browser.viewerRowLimit) }
        else { return }
        tutorial.complete(.fineTuneSourceAdded)
    }
    private func format(_ number: Int) -> String { NumberFormatter.localizedString(from: NSNumber(value: number), number: .decimal) }
}

private struct FineTuneBrowserRow: View {
    let dataset: HFHubDataset
    let isSelected: Bool
    let recommended: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dataset.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                if recommended { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
            }
            Text(dataset.id).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            HStack { Text(dataset.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1); Spacer(); Text(dataset.estimatedRows.map { "\($0) rows" } ?? "\(dataset.downloads ?? 0)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isSelected ? WorkbenchTheme.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
    }
}
