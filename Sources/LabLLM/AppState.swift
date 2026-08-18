import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    // Model-workspace backed configuration. Changing any of these updates the
    // active model's saved definition, so switching models switches the whole setup.
    @Published var gptConfig = GPTConfig() { didSet { markWorkspaceDirty() } }
    @Published var trainConfig = TrainConfig() { didSet { markWorkspaceDirty() } }
    @Published var tokenizerKind: TokenizerKind = .character { didSet { markWorkspaceDirty() } }
    @Published var bpeTargetVocab: Int = 800 { didSet { markWorkspaceDirty() } }

    /// Which installed datasets this model trains on, and how much of each. Mixing
    /// belongs to the run, so it is configured in Training rather than in the
    /// dataset browsers.
    @Published var corpusMix: [DatasetSelection] = [] { didSet { markWorkspaceDirty() } }
    @Published var fineTuneMix: [DatasetSelection] = [] { didSet { markWorkspaceDirty() } }

    /// Materialized training data. Empty until the selected mix is read off disk —
    /// see `prepareCorpus` / `prepareFineTuneData`.
    @Published private(set) var corpus = ""
    @Published private(set) var isCorpusLoaded = false
    @Published private(set) var sftConversations: [[ChatMessage]] = []
    @Published private(set) var isFineTuneDataLoaded = false
    @Published private(set) var isLoadingMix = false

    @Published var tokenizer: Tokenizer?

    @Published var dpoExamples: [PreferenceExample] = []
    @Published var dpoDatasetName = "No preference data selected"
    @Published var datasetImportError: String?
    @Published var pendingContinuation: (url: URL, meta: Checkpoint.Meta)?

    let library = DatasetLibrary()
    let models = ModelStore()
    let dataImport = DataImportState()

    /// Mixes above this size are not loaded automatically on launch or after a
    /// settings change; they are read when a run actually starts.
    private static let autoLoadByteBudget = 64 * 1_024 * 1_024

    private enum ViewerImportKind { case corpus, fineTune }
    private struct ViewerImportJob {
        let dataset: HFHubDataset
        let source: HFViewerSource
        let limit: Int
        let kind: ViewerImportKind
        let priority: Int

        var title: String { dataset.displayName }
    }
    private var viewerImportQueue: [ViewerImportJob] = []
    private var activeDataImportTask: Task<Void, Never>?
    private var workspaceSaveScheduled = false
    private var isApplyingWorkspace = false
    /// Recipe waiting on its dataset download to finish.
    private var pendingRecipe: Recipe?
    private var pendingRecipeDatasetID: UUID?

    // Embedding map
    @Published var embeddingPoints: [EmbeddingPoint] = []
    @Published var isComputingEmbeddings = false

    @Published var trainer = Trainer()
    /// Saved dashboards (loss curve, metrics, samples) for this model, one per run
    /// mode, restored on launch and whenever the studio switches models.
    @Published private(set) var sessions: [RunMode: TrainingSession] = [:]
    let loading = LoadingState()
    let hardware = HardwareInfo.current()

    private var sessionObservers: Set<AnyCancellable> = []

    init() {
        applyActiveWorkspace()
        observeTrainerForSessionSaves()
    }

    // MARK: - Run sessions

    /// Runs report continuously, so saves are throttled while training and forced
    /// once when a run ends (including a stop, which still saves a checkpoint).
    private func observeTrainerForSessionSaves() {
        trainer.$step
            .throttle(for: .seconds(5), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self, self.trainer.isTraining else { return }
                self.captureSession()
            }
            .store(in: &sessionObservers)

        trainer.$isTraining
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isTraining in
                guard let self, !isTraining else { return }
                // The run's final numbers land right after this flips.
                DispatchQueue.main.async { self.captureSession() }
            }
            .store(in: &sessionObservers)
    }

    /// Writes the visible dashboard into this model's `sessions.json`.
    func captureSession() {
        guard let id = models.activeID else { return }
        let snapshot = trainer.sessionSnapshot()
        guard snapshot.step > 0 else { return }
        sessions[snapshot.mode] = snapshot
        TrainingSessionStore.save(sessions, to: models.directory(for: id))
    }

    private func loadSessions() {
        guard let id = models.activeID else { sessions = [:]; return }
        sessions = TrainingSessionStore.load(from: models.directory(for: id))
        if let latest = sessions.values.max(by: { $0.updatedAt < $1.updatedAt }) {
            trainer.restore(session: latest)
        } else {
            trainer.clearSession(mode: .pretrain)
        }
    }

    /// Shows the saved dashboard for a mode when the user switches the Training
    /// page between Pretrain, Fine-tune and DPO.
    func showSession(for mode: RunMode) {
        guard !trainer.isTraining, trainer.runMode != mode || sessions[mode] == nil else { return }
        if let session = sessions[mode] { trainer.restore(session: session) }
        else { trainer.clearSession(mode: mode) }
    }

    func session(for mode: RunMode) -> TrainingSession? { sessions[mode] }

    // MARK: - Model workspaces

    var activeModelName: String { models.activeName }

    /// Persist the current configuration, then switch the studio to another model.
    func activateModel(_ id: UUID) {
        guard id != models.activeID else { return }
        captureSession()
        saveWorkspace()
        models.select(id)
        applyActiveWorkspace()
    }

    func createModel(named name: String) {
        captureSession()
        saveWorkspace()
        let workspace = models.create(named: name)
        models.select(workspace.id)
        applyActiveWorkspace()
    }

    func renameActiveModel(to name: String) {
        guard let id = models.activeID else { return }
        models.rename(id, to: name)
    }

    func duplicateActiveModel() {
        guard let id = models.activeID else { return }
        captureSession()
        saveWorkspace()
        if let copy = models.duplicate(id) {
            models.select(copy.id)
            applyActiveWorkspace()
        }
    }

    func deleteActiveModel() {
        guard let id = models.activeID else { return }
        models.delete(id)
        applyActiveWorkspace()
    }

    /// Loads the active model's saved definition into the studio and resets any
    /// in-memory model/tokenizer that belonged to the previous one.
    private func applyActiveWorkspace() {
        guard let workspace = models.active else { return }
        isApplyingWorkspace = true
        gptConfig = workspace.gptConfig
        trainConfig = workspace.trainConfig
        tokenizerKind = workspace.tokenizerKind
        bpeTargetVocab = workspace.bpeTargetVocab
        corpusMix = pruneMissing(workspace.corpusMix, kind: .corpus)
        fineTuneMix = pruneMissing(workspace.fineTuneMix, kind: .fineTune)
        isApplyingWorkspace = false

        tokenizer = nil
        pendingContinuation = nil
        trainer.unloadModel()
        loadSessions()
        invalidateCorpus()
        invalidateFineTuneData()
        loadMixIfSmall()
    }

    private func pruneMissing(_ mix: [DatasetSelection], kind: InstalledDataset.Kind) -> [DatasetSelection] {
        mix.filter { selection in library.dataset(selection.datasetID)?.kind == kind }
    }

    private func markWorkspaceDirty() {
        guard !isApplyingWorkspace, !workspaceSaveScheduled else { return }
        workspaceSaveScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.workspaceSaveScheduled = false
            self.saveWorkspace()
        }
    }

    func saveWorkspace() {
        guard var workspace = models.active else { return }
        workspace.gptConfig = gptConfig
        workspace.trainConfig = trainConfig
        workspace.tokenizerKind = tokenizerKind
        workspace.bpeTargetVocab = bpeTargetVocab
        workspace.corpusMix = corpusMix
        workspace.fineTuneMix = fineTuneMix
        models.save(workspace)
    }

    // MARK: - Mix summaries (metadata only, no file reads)

    var selectedCorpusDatasets: [(dataset: InstalledDataset, selection: DatasetSelection)] {
        corpusMix.compactMap { selection in
            guard selection.isEnabled, let dataset = library.dataset(selection.datasetID) else { return nil }
            return (dataset, selection)
        }
    }

    var selectedFineTuneDatasets: [(dataset: InstalledDataset, selection: DatasetSelection)] {
        fineTuneMix.compactMap { selection in
            guard selection.isEnabled, let dataset = library.dataset(selection.datasetID) else { return nil }
            return (dataset, selection)
        }
    }

    var corpusCharCount: Int {
        isCorpusLoaded ? corpus.count : selectedCorpusDatasets.reduce(0) { $0 + $1.selection.selectedCharacters(in: $1.dataset) }
    }

    var hasCorpus: Bool { !selectedCorpusDatasets.isEmpty }

    var corpusName: String {
        let selected = selectedCorpusDatasets
        switch selected.count {
        case 0: return "No corpus selected"
        case 1: return selected[0].dataset.name
        default: return "Merged \(selected.count) corpora"
        }
    }

    var sftDatasetName: String {
        let selected = selectedFineTuneDatasets
        switch selected.count {
        case 0: return "No fine-tuning data selected"
        case 1: return selected[0].dataset.name
        default: return "Merged \(selected.count) datasets"
        }
    }

    var sftRowCount: Int {
        isFineTuneDataLoaded ? sftConversations.count
            : selectedFineTuneDatasets.reduce(0) { $0 + $1.selection.selectedRows(in: $1.dataset) }
    }

    var sftPairCount: Int {
        isFineTuneDataLoaded ? sftConversations.reduce(0) { $0 + ConversationImport.pairCount(in: $1) }
            : selectedFineTuneDatasets.reduce(0) { $0 + $1.selection.selectedPairs(in: $1.dataset) }
    }

    var hasFineTuneData: Bool { !selectedFineTuneDatasets.isEmpty }

    private var selectedMixBytes: Int {
        selectedCorpusDatasets.reduce(0) { $0 + $1.dataset.bytes } +
        selectedFineTuneDatasets.reduce(0) { $0 + $1.dataset.bytes }
    }

    // MARK: - Mix editing

    func setMixEnabled(_ enabled: Bool, for datasetID: UUID, kind: InstalledDataset.Kind) {
        update(datasetID, kind: kind) { $0.isEnabled = enabled }
    }

    func setMixLimitMode(_ mode: DatasetLimitMode, for datasetID: UUID, kind: InstalledDataset.Kind) {
        update(datasetID, kind: kind) { $0.limitMode = mode }
    }

    func setMixPercent(_ percent: Double, for datasetID: UUID, kind: InstalledDataset.Kind) {
        update(datasetID, kind: kind) { $0.percent = percent }
    }

    func setMixLineLimit(_ limit: Int, for datasetID: UUID, kind: InstalledDataset.Kind) {
        update(datasetID, kind: kind) { $0.lineLimit = limit }
    }

    func addToMix(_ dataset: InstalledDataset) {
        switch dataset.kind {
        case .corpus:
            guard !corpusMix.contains(where: { $0.datasetID == dataset.id }) else { return }
            corpusMix.append(DatasetSelection(datasetID: dataset.id))
            invalidateCorpus()
        case .fineTune:
            guard !fineTuneMix.contains(where: { $0.datasetID == dataset.id }) else { return }
            fineTuneMix.append(DatasetSelection(datasetID: dataset.id, lineLimit: dataset.rows))
            invalidateFineTuneData()
        }
        loadMixIfSmall()
    }

    func removeFromMix(_ datasetID: UUID, kind: InstalledDataset.Kind) {
        switch kind {
        case .corpus: corpusMix.removeAll { $0.datasetID == datasetID }; invalidateCorpus()
        case .fineTune: fineTuneMix.removeAll { $0.datasetID == datasetID }; invalidateFineTuneData()
        }
        loadMixIfSmall()
    }

    /// Deletes an installed dataset from disk and from every model's mix.
    func uninstall(_ dataset: InstalledDataset) {
        library.remove(dataset)
        for var workspace in models.models {
            let before = workspace.corpusMix.count + workspace.fineTuneMix.count
            workspace.corpusMix.removeAll { $0.datasetID == dataset.id }
            workspace.fineTuneMix.removeAll { $0.datasetID == dataset.id }
            if before != workspace.corpusMix.count + workspace.fineTuneMix.count { models.save(workspace) }
        }
        isApplyingWorkspace = true
        corpusMix.removeAll { $0.datasetID == dataset.id }
        fineTuneMix.removeAll { $0.datasetID == dataset.id }
        isApplyingWorkspace = false
        switch dataset.kind {
        case .corpus: invalidateCorpus()
        case .fineTune: invalidateFineTuneData()
        }
        loadMixIfSmall()
    }

    private func update(_ datasetID: UUID, kind: InstalledDataset.Kind, _ change: (inout DatasetSelection) -> Void) {
        switch kind {
        case .corpus:
            guard let index = corpusMix.firstIndex(where: { $0.datasetID == datasetID }) else { return }
            change(&corpusMix[index])
            invalidateCorpus()
        case .fineTune:
            guard let index = fineTuneMix.firstIndex(where: { $0.datasetID == datasetID }) else { return }
            change(&fineTuneMix[index])
            invalidateFineTuneData()
        }
        loadMixIfSmall()
    }

    private func invalidateCorpus() {
        corpus = ""
        isCorpusLoaded = false
        tokenizer = nil
    }

    private func invalidateFineTuneData() {
        sftConversations = []
        isFineTuneDataLoaded = false
    }

    // MARK: - Materializing the mix

    /// Reads whatever the mix needs from disk without blocking the UI. Small mixes
    /// load on their own; anything large waits until a run is actually started.
    private func loadMixIfSmall() {
        guard selectedMixBytes <= Self.autoLoadByteBudget else { return }
        if !isCorpusLoaded && hasCorpus { prepareCorpus() }
        if !isFineTuneDataLoaded && hasFineTuneData { prepareFineTuneData() }
    }

    func prepareCorpus(then completion: (() -> Void)? = nil) {
        guard !isCorpusLoaded else { completion?(); return }
        let plan = selectedCorpusDatasets.map { (url: library.fileURL(for: $0.dataset), selection: $0.selection) }
        guard !plan.isEmpty else { corpus = ""; isCorpusLoaded = true; completion?(); return }
        isLoadingMix = true
        DispatchQueue.global(qos: .userInitiated).async {
            var parts: [String] = []
            var failures: [String] = []
            for item in plan {
                guard let text = try? String(contentsOf: item.url, encoding: .utf8) else {
                    failures.append(item.url.deletingLastPathComponent().lastPathComponent)
                    continue
                }
                parts.append(Self.limited(text: text, selection: item.selection))
            }
            let merged = parts.joined(separator: "\n\n")
            DispatchQueue.main.async {
                self.corpus = merged
                self.isCorpusLoaded = true
                self.isLoadingMix = false
                self.tokenizer = nil
                if !failures.isEmpty {
                    self.datasetImportError = "\(failures.count) installed corpus file(s) couldn't be read and were skipped."
                }
                completion?()
            }
        }
    }

    func prepareFineTuneData(then completion: (() -> Void)? = nil) {
        guard !isFineTuneDataLoaded else { completion?(); return }
        let plan = selectedFineTuneDatasets.map { (url: library.fileURL(for: $0.dataset), selection: $0.selection) }
        guard !plan.isEmpty else { sftConversations = []; isFineTuneDataLoaded = true; completion?(); return }
        isLoadingMix = true
        DispatchQueue.global(qos: .userInitiated).async {
            var merged: [[ChatMessage]] = []
            for item in plan {
                guard let raw = try? String(contentsOf: item.url, encoding: .utf8) else { continue }
                let parsed = ConversationImport.parseJSONL(raw)
                merged.append(contentsOf: parsed.prefix(item.selection.selectedCount(of: parsed.count)))
            }
            DispatchQueue.main.async {
                self.sftConversations = merged
                self.isFineTuneDataLoaded = true
                self.isLoadingMix = false
                completion?()
            }
        }
    }

    nonisolated private static func limited(text: String, selection: DatasetSelection) -> String {
        switch selection.limitMode {
        case .percent:
            guard selection.percent < 100 else { return text }
            let count = max(1, Int((Double(text.count) * selection.percent / 100).rounded()))
            return String(text.prefix(count))
        case .lines:
            guard selection.lineLimit > 0 else { return "" }
            return text.split(separator: "\n", omittingEmptySubsequences: false)
                .prefix(selection.lineLimit).joined(separator: "\n")
        }
    }

    // MARK: - Tokenizers

    func buildTokenizer() {
        prepareCorpus { [weak self] in
            guard let self else { return }
            let tok: Tokenizer = self.tokenizerKind == .byte ? .byte() : .character(from: self.corpus)
            self.tokenizer = tok
            self.gptConfig.vocabSize = tok.vocabSize
        }
    }

    /// Trains a real BPE tokenizer on the current corpus. Runs off the main thread
    /// since training is O(merges × corpus) and would otherwise freeze the UI.
    func buildBPETokenizer() {
        prepareCorpus { [weak self] in
            guard let self else { return }
            self.loading.begin("Training BPE tokenizer", detail: "0%")
            let text = self.corpus
            let target = self.bpeTargetVocab
            let loading = self.loading
            DispatchQueue.global(qos: .userInitiated).async {
                let tok = Tokenizer.bpeTrained(from: text, targetVocabSize: target) { p in
                    loading.update(detail: "\(Int(p * 100))%", progress: p)
                }
                DispatchQueue.main.async {
                    self.tokenizer = tok
                    self.gptConfig.vocabSize = tok.vocabSize
                    self.loading.end()
                }
            }
        }
    }

    // MARK: - Installing data

    func loadCorpus(from url: URL) {
        loading.begin("Loading corpus", detail: "0% · \(url.lastPathComponent)")
        let loading = loading
        DispatchQueue.global().async {
            let text: String
            do {
                text = try Self.readUTF8Text(from: url, progress: { completed, total in
                    loading.update(detail: "\(Self.percent(completed, total)) · \(Self.formatBytes(completed)) of \(Self.formatBytes(total))", progress: Double(completed) / Double(max(total, 1)))
                })
            } catch {
                text = ""
            }
            DispatchQueue.main.async {
                self.installCorpus(name: url.lastPathComponent, origin: "Local text", text: text)
                self.loading.end()
            }
        }
    }

    func downloadHFCorpus(_ dataset: HFHubDataset, file: HFHubFile) {
        dataImport.begin(title: "Downloading pre-training data", detail: dataset.id, totalRows: max(1, file.size ?? 1), queuedTitles: [], unit: "bytes")
        activeDataImportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await HFDownloader.download(repo: dataset.id, filePath: file.path) { completed, total in
                    Task { @MainActor [weak self] in
                        self?.dataImport.update(completedRows: Int(min(completed, Int64(Int.max))),
                                                detail: "\(Self.formatBytes(completed)) of \(total.map(Self.formatBytes) ?? "unknown size") from \(dataset.displayName)")
                        self?.dataImport.totalRows = Int(min(total ?? max(completed, 1), Int64(Int.max)))
                    }
                }
                await MainActor.run {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        self.datasetImportError = "That corpus file was empty."
                        self.finishViewerImport(error: nil)
                        return
                    }
                    self.installCorpus(name: dataset.displayName, origin: "Hugging Face · \(dataset.id)", text: text)
                    self.finishViewerImport(error: nil)
                }
            } catch is CancellationError {
                await MainActor.run { self.finishViewerImport(error: nil) }
            } catch {
                await MainActor.run {
                    self.finishViewerImport(error: error.localizedDescription)
                }
            }
        }
    }

    func importHFViewerCorpus(_ dataset: HFHubDataset, source: HFViewerSource, limit: Int) {
        enqueueViewerImport(.init(dataset: dataset, source: source, limit: limit, kind: .corpus, priority: 100))
    }

    /// Writes an imported corpus into the on-disk library and adds it to this
    /// model's mix, so it is still there after a relaunch.
    @discardableResult
    func installCorpus(name: String, origin: String, text: String) -> InstalledDataset? {
        do {
            let entry = try library.installCorpus(name: name, origin: origin, text: text)
            addToMix(entry)
            finishRecipeInstallIfNeeded(entry)
            return entry
        } catch {
            datasetImportError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func installFineTuneData(name: String, origin: String, conversations: [[ChatMessage]]) -> InstalledDataset? {
        do {
            let entry = try library.installFineTune(name: name, origin: origin, conversations: conversations)
            addToMix(entry)
            finishRecipeInstallIfNeeded(entry)
            return entry
        } catch {
            datasetImportError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Recipes

    /// Progress of the recipe currently being set up, so the launcher can report
    /// what it is doing instead of silently downloading in the background.
    @Published var recipeStatus: String?

    /// Applies a recipe end to end: architecture, hyperparameters and tokenizer,
    /// then the dataset it needs (installing it from the Hub when missing), then
    /// hands the user to Training on the right mode, ready to start.
    func run(_ recipe: Recipe, inNewModel: Bool) {
        if inNewModel { createModel(named: recipe.name) }

        tokenizerKind = recipe.tokenizer
        var config = recipe.gpt
        config.vocabSize = gptConfig.vocabSize
        gptConfig = config
        trainConfig = recipe.train
        tokenizer = nil

        prepareRecipeData(recipe)

        NotificationCenter.default.post(name: .prepareTrainingContinuation,
                                        object: recipe.mode == .sft ? "sft" : recipe.mode == .dpo ? "dpo" : "pretrain")
        NotificationCenter.default.post(name: .navigateToSection, object: NavSection.training.rawValue)
    }

    /// True when this recipe's dataset is already in the library.
    func installedDataset(for recipe: Recipe) -> InstalledDataset? {
        library.datasets.first { $0.kind == recipe.data.kind && $0.origin.contains(recipe.data.repo) }
    }

    private func prepareRecipeData(_ recipe: Recipe) {
        // Start from a clean mix for the kind this recipe trains on, so a recipe
        // never silently inherits whatever the previous run happened to use.
        switch recipe.data.kind {
        case .corpus: corpusMix.removeAll(); invalidateCorpus()
        case .fineTune: fineTuneMix.removeAll(); invalidateFineTuneData()
        }

        if let installed = installedDataset(for: recipe) {
            addToMix(installed)
            applyRecipeShare(recipe, to: installed)
            recipeStatus = "\(recipe.name) is ready — \(installed.name) is already installed."
            return
        }
        downloadRecipeDataset(recipe)
    }

    private func applyRecipeShare(_ recipe: Recipe, to dataset: InstalledDataset) {
        guard recipe.corpusPercent < 100 else { return }
        setMixPercent(recipe.corpusPercent, for: dataset.id, kind: dataset.kind)
    }

    /// Finds a usable file in the recipe's repository (preferring the one the
    /// recipe names) and falls back to the Dataset Viewer when the repo stores its
    /// data as Parquet.
    private func downloadRecipeDataset(_ recipe: Recipe) {
        let target = recipe.data
        recipeStatus = "Installing \(target.title) for \(recipe.name)…"
        let dataset = HFHubDataset(id: target.repo, title: target.title)
        let hubKind: HFHubBrowser.Kind = target.kind == .corpus ? .corpus : .fineTune
        pendingRecipeDatasetID = nil

        Task { [weak self] in
            guard let self else { return }
            let files = (try? await HFHubClient.compatibleFiles(repo: target.repo, kind: hubKind, limit: 40)) ?? []
            let preferred = target.fileContains.flatMap { hint in
                files.first { $0.path.localizedCaseInsensitiveContains(hint) }
            }
            let chosen = preferred ?? files.first { $0.path.localizedCaseInsensitiveContains("train") } ?? files.first

            if let chosen {
                await MainActor.run {
                    self.pendingRecipe = recipe
                    if target.kind == .corpus { self.downloadHFCorpus(dataset, file: chosen) }
                    else { self.downloadHFDataset(dataset, file: chosen) }
                }
                return
            }

            let source = try? await HFHubClient.viewerSource(repo: target.repo)
            await MainActor.run {
                guard let source else {
                    self.recipeStatus = nil
                    self.datasetImportError = "Couldn't find an importable file for \(target.repo). Install the data from the dataset browser and run the recipe again."
                    return
                }
                self.pendingRecipe = recipe
                if target.kind == .corpus {
                    self.importHFViewerCorpus(dataset, source: source, limit: target.rowLimit)
                } else {
                    self.importHFViewerDataset(dataset, source: source, limit: target.rowLimit)
                }
            }
        }
    }

    /// Applies the recipe's share once its dataset finishes installing.
    private func finishRecipeInstallIfNeeded(_ dataset: InstalledDataset) {
        guard let recipe = pendingRecipe, recipe.data.kind == dataset.kind else { return }
        applyRecipeShare(recipe, to: dataset)
        recipeStatus = "\(recipe.name) is ready — \(dataset.name) installed."
        pendingRecipe = nil
    }

    // MARK: - Training entry points

    func startTraining(resumeFrom: URL? = nil) {
        guard hasCorpus else { datasetImportError = "Choose at least one installed corpus in the training data panel before starting training."; return }
        do {
            try MLXMetalLibrary.ensureAvailable()
        } catch {
            datasetImportError = "Couldn't prepare MLX Metal: \(error.localizedDescription)"
            return
        }
        loading.begin("Preparing training", detail: "Reading the selected training mix…")
        prepareCorpus { [weak self] in
            guard let self else { return }
            guard !self.corpus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.loading.end()
                self.datasetImportError = "The selected corpus files are empty. Adjust the training mix and try again."
                return
            }
            if let resumeFrom, let meta = try? Checkpoint.loadMeta(from: resumeFrom) {
                self.gptConfig = meta.config
                self.tokenizer = meta.tokenizer
            } else if self.tokenizer == nil {
                let tok: Tokenizer = self.tokenizerKind == .byte ? .byte() : .character(from: self.corpus)
                self.tokenizer = tok
                self.gptConfig.vocabSize = tok.vocabSize
            }
            guard let tok = self.tokenizer else { self.loading.end(); return }
            self.loading.update(detail: "Building model and dataset…", progress: nil)
            self.trainer.start(gptConfig: self.gptConfig, trainConfig: self.trainConfig, tokenizer: tok, corpus: self.corpus,
                               hardware: self.hardware, datasetName: self.corpusName, resumeFrom: resumeFrom)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.loading.end() }
        }
    }

    func startSFT(useLoRA: Bool, resumeFrom: URL? = nil) {
        guard hasFineTuneData else { datasetImportError = "Select at least one installed fine-tuning dataset in the training data panel."; return }
        do {
            try MLXMetalLibrary.ensureAvailable()
        } catch {
            datasetImportError = "Couldn't prepare MLX Metal: \(error.localizedDescription)"
            return
        }
        loading.begin("Preparing fine-tuning", detail: "Reading the selected fine-tuning mix…")
        prepareFineTuneData { [weak self] in
            guard let self else { return }
            guard !self.sftConversations.isEmpty else {
                self.loading.end()
                self.datasetImportError = "No usable rows were found in the selected fine-tuning mix."
                return
            }
            if let resumeFrom, let meta = try? Checkpoint.loadMeta(from: resumeFrom) {
                self.gptConfig = meta.config
                self.tokenizer = meta.tokenizer
                self.finishSFT(useLoRA: useLoRA, resumeFrom: resumeFrom)
            } else if self.tokenizer == nil {
                // A chat tokenizer still needs a vocabulary; derive it from the corpus
                // mix when one is selected, otherwise from the conversations themselves.
                self.prepareCorpus { [weak self] in
                    guard let self else { return }
                    let source = self.corpus.isEmpty
                        ? self.sftConversations.flatMap { $0 }.map(\.content).joined(separator: "\n")
                        : self.corpus
                    let tok: Tokenizer = self.tokenizerKind == .byte ? .byte() : .character(from: source)
                    self.tokenizer = tok
                    self.gptConfig.vocabSize = tok.vocabSize
                    self.finishSFT(useLoRA: useLoRA, resumeFrom: resumeFrom)
                }
            } else {
                self.finishSFT(useLoRA: useLoRA, resumeFrom: resumeFrom)
            }
        }
    }

    private func finishSFT(useLoRA: Bool, resumeFrom: URL?) {
        guard let tok = tokenizer else { loading.end(); return }
        loading.update(detail: "Building chat batches with loss masking…", progress: nil)
        trainer.startSFT(gptConfig: gptConfig, trainConfig: trainConfig, tokenizer: tok,
                         conversations: sftConversations, useLoRA: useLoRA,
                         hardware: hardware, datasetName: sftDatasetName, resumeFrom: resumeFrom)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.loading.end() }
    }

    func startDPO() {
        do {
            try MLXMetalLibrary.ensureAvailable()
        } catch {
            datasetImportError = "Couldn't prepare MLX Metal: \(error.localizedDescription)"
            return
        }
        loading.begin("Preparing DPO", detail: "Building preference pairs…")
        trainer.startDPO(trainConfig: trainConfig, examples: dpoExamples, hardware: hardware)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.loading.end() }
    }

    func loadCheckpoint(_ url: URL, meta: Checkpoint.Meta) {
        do {
            try MLXMetalLibrary.ensureAvailable()
        } catch {
            datasetImportError = "Couldn't prepare MLX Metal: \(error.localizedDescription)"
            return
        }
        loading.begin("Loading checkpoint", detail: url.lastPathComponent)
        DispatchQueue.global().async {
            do {
                let model = try Checkpoint.loadModel(from: url, meta: meta)
                DispatchQueue.main.async {
                    self.gptConfig = meta.config
                    self.tokenizer = meta.tokenizer
                    self.tokenizerKind = meta.tokenizer.kind
                    self.trainer.loadForSampling(model: model, tokenizer: meta.tokenizer)
                    self.loading.end()
                }
            } catch {
                DispatchQueue.main.async {
                    self.datasetImportError = "Couldn't load checkpoint: \(error.localizedDescription)"
                    self.loading.end()
                }
            }
        }
    }

    func prepareContinuation(from url: URL, meta: Checkpoint.Meta, asFineTune: Bool) {
        guard meta.quantizedBits == nil else {
            datasetImportError = "Quantized checkpoints can be sampled but not continued for training. Load the original checkpoint instead."
            return
        }
        pendingContinuation = (url, meta)
        gptConfig = meta.config
        tokenizer = meta.tokenizer
        NotificationCenter.default.post(name: .prepareTrainingContinuation, object: asFineTune ? "sft" : "pretrain")
        NotificationCenter.default.post(name: .navigateToSection, object: "Training")
    }

    // MARK: - Dataset import (SFT)

    func importLocalJSONL(url: URL) {
        loading.begin("Importing dataset", detail: "0% · \(url.lastPathComponent)")
        let loading = loading
        DispatchQueue.global().async {
            guard let text = try? Self.readUTF8Text(from: url, progress: { completed, total in
                loading.update(detail: "\(Self.percent(completed, total)) · \(Self.formatBytes(completed)) of \(Self.formatBytes(total))", progress: Double(completed) / Double(max(total, 1)))
            }) else {
                DispatchQueue.main.async {
                    self.datasetImportError = "Couldn't read that file as UTF-8 text."
                    self.loading.end()
                }
                return
            }
            loading.update(detail: "Parsing rows…", progress: nil)
            let convs = url.pathExtension.lowercased() == "json" ? ConversationImport.parseJSON(text) : ConversationImport.parseJSONL(text)
            DispatchQueue.main.async {
                if convs.isEmpty {
                    self.datasetImportError = ConversationImportError.noValidRows.localizedDescription
                } else {
                    self.installFineTuneData(name: url.lastPathComponent, origin: "Local JSONL", conversations: convs)
                }
                self.loading.end()
            }
        }
    }

    func downloadHFDataset(_ dataset: HFHubDataset, file: HFHubFile) {
        dataImport.begin(title: "Downloading fine-tuning data", detail: dataset.id, totalRows: max(1, file.size ?? 1), queuedTitles: [], unit: "bytes")
        activeDataImportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await HFDownloader.download(repo: dataset.id, filePath: file.path) { completed, total in
                    Task { @MainActor [weak self] in
                        self?.dataImport.update(completedRows: Int(min(completed, Int64(Int.max))),
                                                detail: "\(Self.formatBytes(completed)) of \(total.map(Self.formatBytes) ?? "unknown size") from \(dataset.displayName)")
                        self?.dataImport.totalRows = Int(min(total ?? max(completed, 1), Int64(Int.max)))
                    }
                }
                let convs = file.path.lowercased().hasSuffix(".json") ? ConversationImport.parseJSON(text) : ConversationImport.parseJSONL(text)
                await MainActor.run {
                    if convs.isEmpty {
                        self.finishViewerImport(error: "Downloaded the file, but no rows matched a recognized instruction or conversation format. Choose another JSON or JSONL file from this dataset.")
                    } else {
                        self.installFineTuneData(name: dataset.displayName, origin: "Hugging Face · \(dataset.id)", conversations: convs)
                        self.dataImport.update(completedRows: convs.count, detail: "Installed \(convs.count.formatted()) rows with \(ConversationImport.pairCount(in: convs.flatMap { $0 }).formatted()) fine-tuning pairs")
                        self.finishViewerImport(error: nil)
                    }
                }
            } catch is CancellationError {
                await MainActor.run { self.finishViewerImport(error: nil) }
            } catch {
                await MainActor.run {
                    self.finishViewerImport(error: error.localizedDescription)
                }
            }
        }
    }

    func importHFViewerDataset(_ dataset: HFHubDataset, source: HFViewerSource, limit: Int) {
        enqueueViewerImport(.init(dataset: dataset, source: source, limit: limit, kind: .fineTune, priority: 100))
    }

    func cancelActiveDataImport() {
        guard activeDataImportTask != nil else { return }
        dataImport.isCancelling = true
        activeDataImportTask?.cancel()
    }

    private func enqueueViewerImport(_ job: ViewerImportJob) {
        viewerImportQueue.append(job)
        viewerImportQueue.sort { $0.priority > $1.priority }
        dataImport.updateQueue(viewerImportQueue.map(\.title))
        startNextViewerImportIfNeeded()
    }

    private func startNextViewerImportIfNeeded() {
        guard activeDataImportTask == nil, !viewerImportQueue.isEmpty else { return }
        let job = viewerImportQueue.removeFirst()
        dataImport.begin(
            title: job.kind == .corpus ? "Importing pre-training data" : "Importing fine-tuning data",
            detail: "Preparing \(job.title)",
            totalRows: min(job.limit, job.source.totalRows),
            queuedTitles: viewerImportQueue.map(\.title)
        )
        activeDataImportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let rows = try await HFHubClient.viewerRows(repo: job.dataset.id, source: job.source, limit: job.limit) { completed, total in
                    Task { @MainActor [weak self] in
                        self?.dataImport.update(completedRows: completed, detail: "Processed \(completed.formatted()) of \(total.formatted()) rows from \(job.title)")
                    }
                }
                try Task.checkCancellation()
                self.commitViewerImport(job, rows: rows)
            } catch is CancellationError {
                self.finishViewerImport(error: nil)
            } catch {
                self.finishViewerImport(error: error.localizedDescription)
            }
        }
    }

    private func commitViewerImport(_ job: ViewerImportJob, rows: [[String: HFJSONValue]]) {
        switch job.kind {
        case .corpus:
            let text = rows.compactMap(ConversationImport.pretrainingText(from:)).joined(separator: "\n\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                finishViewerImport(error: "This dataset has no recognizable text column to use for pre-training.")
                return
            }
            installCorpus(name: job.dataset.displayName, origin: "Hugging Face Viewer · \(job.dataset.id)", text: text)
        case .fineTune:
            let conversations = ConversationImport.conversations(from: rows)
            guard !conversations.isEmpty else {
                finishViewerImport(error: "This dataset doesn't expose recognized messages, instruction/output, or prompt/response columns.")
                return
            }
            installFineTuneData(name: job.dataset.displayName, origin: "Hugging Face Viewer · \(job.dataset.id)", conversations: conversations)
        }
        finishViewerImport(error: nil)
    }

    private func finishViewerImport(error: String?) {
        activeDataImportTask = nil
        if let error { datasetImportError = error }
        if viewerImportQueue.isEmpty { dataImport.finish() }
        else { startNextViewerImportIfNeeded() }
    }

    func importIMessageDatabase(url: URL) {
        loading.begin("Importing iMessage chats", detail: url.lastPathComponent)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let conversations = try ConversationImport.parseIMessageDatabase(at: url)
                DispatchQueue.main.async {
                    guard !conversations.isEmpty else {
                        self.datasetImportError = "No usable text conversations were found. Choose chat.db and allow Full Disk Access for LabLLM if macOS blocks it."
                        self.loading.end()
                        return
                    }
                    self.installFineTuneData(name: "iMessage chats", origin: "Local iMessage database", conversations: conversations)
                    self.loading.end()
                }
            } catch {
                DispatchQueue.main.async {
                    self.datasetImportError = error.localizedDescription
                    self.loading.end()
                }
            }
        }
    }

    nonisolated private static func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    nonisolated private static func percent(_ completed: Int64, _ total: Int64) -> String {
        "\(Int((Double(completed) / Double(max(total, 1)) * 100).rounded()))%"
    }

    nonisolated private static func readUTF8Text(from url: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let total = Int64(values.fileSize ?? 0)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var data = Data()
        if total > 0 { data.reserveCapacity(Int(min(total, Int64(Int.max)))) }
        var completed: Int64 = 0
        let chunkSize = 512 * 1024
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: chunkSize)
            guard !chunk.isEmpty else { return false }
            data.append(chunk)
            completed += Int64(chunk.count)
            progress(completed, max(total, completed))
            return true
        }) {}
        progress(max(completed, total), max(total, completed))
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConversationImportError.network("Couldn't read that file as UTF-8 text.")
        }
        return text
    }

    // MARK: - Embedding visualization

    func computeEmbeddingMap() {
        guard let model = trainer.model, let tok = trainer.tokenizer else { return }
        isComputingEmbeddings = true
        DispatchQueue.global(qos: .userInitiated).async {
            let points = EmbeddingMap.compute(model: model, tokenizer: tok)
            DispatchQueue.main.async {
                self.embeddingPoints = points
                self.isComputingEmbeddings = false
            }
        }
    }

    func relaxEmbeddingMap() {
        guard !embeddingPoints.isEmpty else { return }
        var pts = embeddingPoints
        EmbeddingMap.relax(&pts)
        embeddingPoints = pts
    }

    // MARK: - Quantization

    func quantizeCheckpoint(_ url: URL, bits: Int, completion: @escaping (Result<(URL, Int, Int), Error>) -> Void) {
        loading.begin("Quantizing", detail: "\(bits)-bit…")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try Checkpoint.saveQuantized(from: url, bits: bits, hardware: self.hardware)
                DispatchQueue.main.async { self.loading.end(); completion(.success(result)) }
            } catch {
                DispatchQueue.main.async { self.loading.end(); completion(.failure(error)) }
            }
        }
    }
}
