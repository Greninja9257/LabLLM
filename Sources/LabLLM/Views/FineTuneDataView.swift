import SwiftUI
import UniformTypeIdentifiers

struct FineTuneDataView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var tutorial: TutorialState
    @StateObject private var browser = HFHubBrowser(kind: .fineTune)
    @State private var importingSFT = false
    @State private var importingIMessage = false

    private var displayedResults: [HFHubDataset] {
        guard prefs.mode == .simple else { return browser.results }
        let remote = browser.results.filter { remote in !browser.pinned.contains(where: { $0.id == remote.id }) }
        return browser.pinned + remote.sorted { ($0.downloads ?? 0) > ($1.downloads ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkbenchPageHeader(eyebrow: "Dataset Studio", title: "Fine-tuning Data", subtitle: "Find compatible instruction datasets, inspect their JSONL files, and compose the exact mix for SFT.", icon: "tray.full")
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
                Text("Results prioritize importable instruction and conversation data, including Parquet-backed datasets.").font(.caption).foregroundStyle(.secondary)
            }
            if browser.isLoading && browser.results.isEmpty { ProgressView("Searching datasets…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(displayedResults) { dataset in
                            FineTuneBrowserRow(dataset: dataset, isSelected: browser.selected == dataset)
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
                        Button(prefs.mode == .simple ? "Download and use" : "Add to fine-tuning mix") { importSelected(dataset) }
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
                        else { FineTuneMarkdownPreview(markdown: browser.readme) }
                    }
                    if !state.sftSources.isEmpty { mixer }
                }.padding(WorkbenchTheme.pagePadding)
            }
        } else {
            WorkbenchEmptyState(icon: "rectangle.and.text.magnifyingglass", title: "Select a dataset", message: "Inspect a compatible JSONL dataset before adding it to your fine-tuning mix.").padding(WorkbenchTheme.pagePadding)
        }
    }

    private var mixer: some View {
        GroupBox("Fine-tuning mix") {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(state.sftConversations.count) selected conversations · \(state.sftPairCount) pairs").font(.headline)
                ForEach($state.sftSources) { $source in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle(source.name, isOn: $source.isEnabled).toggleStyle(.checkbox)
                            Spacer()
                            Text("\(source.selectedCount) rows · \(source.selectedPairCount) pairs")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Picker("Selection", selection: $source.limitMode) { ForEach(DatasetLimitMode.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented)
                        if source.limitMode == .percent {
                            HStack { Slider(value: $source.percent, in: 1...100, step: 1); Text("\(Int(source.percent))%").font(.caption.monospacedDigit()).frame(width: 42) }
                        } else {
                            Stepper("\(source.lineLimit) rows", value: $source.lineLimit, in: 1...max(1, source.conversations.count))
                        }
                    }
                    .padding(10).background(WorkbenchTheme.elevatedPanel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
                    .onChange(of: source.isEnabled) { _ in state.rebuildSFTMix() }
                    .onChange(of: source.limitMode) { _ in state.rebuildSFTMix() }
                    .onChange(of: source.percent) { _ in state.rebuildSFTMix() }
                    .onChange(of: source.lineLimit) { _ in state.rebuildSFTMix() }
                }
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

private struct FineTuneMarkdownPreview: View {
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

private struct FineTuneBrowserRow: View {
    let dataset: HFHubDataset
    let isSelected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dataset.displayName).font(.callout.weight(.semibold)).lineLimit(1)
            Text(dataset.id).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            HStack { Text(dataset.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1); Spacer(); Text(dataset.estimatedRows.map { "\($0) rows" } ?? "\(dataset.downloads ?? 0)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isSelected ? WorkbenchTheme.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
    }
}
