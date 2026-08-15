import SwiftUI
import UniformTypeIdentifiers

struct DatasetView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var tutorial: TutorialState
    @StateObject private var browser = HFHubBrowser(kind: .corpus)
    @State private var importing = false

    private var displayedResults: [HFHubDataset] {
        guard prefs.mode == .simple else { return browser.results }
        let remote = browser.results.filter { remote in !browser.pinned.contains(where: { $0.id == remote.id }) }
        return browser.pinned + remote.sorted { ($0.downloads ?? 0) > ($1.downloads ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkbenchPageHeader(eyebrow: "Dataset Studio", title: "Pre-Training Data", subtitle: "Browse public Hugging Face corpora, inspect their source files, then combine exactly the text you want to train on.", icon: "text.book.closed")
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
            if !browser.activityDetail.isEmpty {
                Text(browser.activityDetail).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            if prefs.mode == .simple && prefs.showDatasetHints {
                Label("Recommended sources are pinned first. Simple mode downloads the selected source automatically.", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if browser.isLoading && browser.results.isEmpty {
                ProgressView("Searching datasets…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(displayedResults, id: \.displayName) { dataset in
                            DatasetBrowserRow(dataset: dataset, isSelected: browser.selected == dataset, recommended: prefs.mode == .simple && dataset.downloads == displayedResults.first?.downloads)
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
        .padding(16)
        .background(WorkbenchTheme.panel)
    }

    @ViewBuilder private var inspectorPane: some View {
        if let dataset = browser.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(dataset.displayName).font(.title2.bold())
                            Text(dataset.id).font(.callout.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(prefs.mode == .simple ? "Download and use" : "Import corpus") { importSelected(dataset) }
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
                        else { MarkdownPreview(markdown: browser.readme) }
                    }
                    if state.corpusSources.count > 1 { corpusMix }
                }.padding(WorkbenchTheme.pagePadding)
            }
        } else {
            WorkbenchEmptyState(icon: "rectangle.and.text.magnifyingglass", title: "Select a dataset", message: "Search or browse the list to inspect a public dataset before importing it.")
                .padding(WorkbenchTheme.pagePadding)
        }
    }

    private var corpusMix: some View {
        GroupBox("Training mix") {
            if state.corpusSources.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(state.corpusName) · \(format(state.corpusCharCount)) characters").font(.headline)
                    ForEach($state.corpusSources) { $source in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Toggle(source.name, isOn: $source.isEnabled).toggleStyle(.checkbox)
                                Spacer()
                                Text("\(Int(source.percent))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Slider(value: $source.percent, in: 1...100, step: 1)
                        }
                        .onChange(of: source.isEnabled) { _ in state.rebuildCorpusMix() }
                        .onChange(of: source.percent) { _ in state.rebuildCorpusMix() }
                    }
                }
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

private struct MarkdownPreview: View {
    let markdown: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                    let text = String(line)
                    if text.hasPrefix("### ") { Text(String(text.dropFirst(4))).font(.headline) }
                    else if text.hasPrefix("## ") { Text(String(text.dropFirst(3))).font(.title3.bold()) }
                    else if text.hasPrefix("# ") { Text(String(text.dropFirst(2))).font(.title2.bold()) }
                    else if text.hasPrefix("- ") { Label(String(text.dropFirst(2)), systemImage: "circle.fill").font(.callout).foregroundStyle(.secondary) }
                    else if !text.isEmpty { Text(text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: 360)
    }
}

private struct DatasetBrowserRow: View {
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
            HStack(spacing: 8) {
                Text(dataset.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(dataset.downloadSize ?? "\(dataset.downloads ?? 0)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isSelected ? WorkbenchTheme.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
    }
}
