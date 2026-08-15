import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var gptConfig = GPTConfig()
    @Published var trainConfig = TrainConfig()
    @Published var tokenizerKind: TokenizerKind = .character
    @Published var bpeTargetVocab: Int = 800

    @Published var corpus = ""
    @Published var corpusName = "No corpus selected"
    @Published var corpusSources: [CorpusSource] = []
    @Published var tokenizer: Tokenizer?

    // SFT / DPO data currently loaded
    @Published var sftConversations: [[ChatMessage]] = []
    @Published var sftDatasetName = "No fine-tuning data selected"
    @Published var sftSources: [SFTDataSource] = []
    @Published var dpoExamples: [PreferenceExample] = []
    @Published var dpoDatasetName = "No preference data selected"
    @Published var datasetImportError: String?
    @Published var pendingContinuation: (url: URL, meta: Checkpoint.Meta)?
    let dataImport = DataImportState()

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

    // Embedding map
    @Published var embeddingPoints: [EmbeddingPoint] = []
    @Published var isComputingEmbeddings = false

    @Published var trainer = Trainer()
    let loading = LoadingState()
    let hardware = HardwareInfo.current()

    var corpusCharCount: Int { corpus.count }
    var hasCorpus: Bool { !corpus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var sftPairCount: Int {
        sftConversations.reduce(0) { $0 + ConversationImport.pairCount(in: $1) }
    }

    func buildTokenizer() {
        let tok: Tokenizer = tokenizerKind == .byte ? .byte() : .character(from: corpus)
        tokenizer = tok
        gptConfig.vocabSize = tok.vocabSize
    }

    /// Trains a real BPE tokenizer on the current corpus. Runs off the main thread
    /// since training is O(merges × corpus) and would otherwise freeze the UI.
    func buildBPETokenizer() {
        loading.begin("Training BPE tokenizer", detail: "0%")
        let text = corpus
        let target = bpeTargetVocab
        let loading = loading
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
                self.addCorpusSource(name: url.lastPathComponent, origin: "Local text", text: text)
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
                    self.addCorpusSource(name: dataset.displayName, origin: "Hugging Face · \(dataset.id)", text: text)
                    self.tokenizer = nil
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

    func addCorpusSource(name: String, origin: String, text: String) {
        corpusSources.append(CorpusSource(name: name, origin: origin, text: text))
        rebuildCorpusMix()
    }

    func rebuildCorpusMix() {
        let enabled = corpusSources.filter(\.isEnabled)
        corpus = enabled.map(\.selectedText).joined(separator: "\n\n")
        corpusName = enabled.isEmpty ? "No corpus selected" : enabled.count == 1 ? enabled[0].name : "Merged \(enabled.count) corpora"
        tokenizer = nil
    }

    func apply(_ recipe: Recipe) {
        tokenizerKind = recipe.tokenizer
        let tok: Tokenizer = recipe.tokenizer == .byte ? .byte() : .character(from: corpus)
        tokenizer = tok
        var g = recipe.gpt
        g.vocabSize = tok.vocabSize
        gptConfig = g
        trainConfig = recipe.train
    }

    // MARK: - Training entry points

    func startTraining(resumeFrom: URL? = nil) {
        guard hasCorpus else { datasetImportError = "Choose at least one text corpus before starting training."; return }
        do {
            try MLXMetalLibrary.ensureAvailable()
        } catch {
            datasetImportError = "Couldn't prepare MLX Metal: \(error.localizedDescription)"
            return
        }
        if let resumeFrom, let meta = try? Checkpoint.loadMeta(from: resumeFrom) {
            gptConfig = meta.config
            tokenizer = meta.tokenizer
        } else if tokenizer == nil { buildTokenizer() }
        guard let tok = tokenizer else { return }
        loading.begin("Preparing training", detail: "Building model and dataset…")
        trainer.start(gptConfig: gptConfig, trainConfig: trainConfig, tokenizer: tok, corpus: corpus,
                     hardware: hardware, datasetName: corpusName, resumeFrom: resumeFrom)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.loading.end() }
    }

    func startSFT(useLoRA: Bool, resumeFrom: URL? = nil) {
        guard !sftConversations.isEmpty else { datasetImportError = "Add at least one compatible JSONL dataset before starting fine-tuning."; return }
        do {
            try MLXMetalLibrary.ensureAvailable()
        } catch {
            datasetImportError = "Couldn't prepare MLX Metal: \(error.localizedDescription)"
            return
        }
        if let resumeFrom, let meta = try? Checkpoint.loadMeta(from: resumeFrom) {
            gptConfig = meta.config
            tokenizer = meta.tokenizer
        } else if tokenizer == nil { buildTokenizer() }
        guard let tok = tokenizer else { return }
        loading.begin("Preparing fine-tuning", detail: "Building chat batches with loss masking…")
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
                    self.addSFTSource(name: url.lastPathComponent, origin: "Local JSONL", conversations: convs)
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
                        self.addSFTSource(name: dataset.displayName, origin: "Hugging Face · \(dataset.id)", conversations: convs)
                        self.dataImport.update(completedRows: convs.count, detail: "Imported \(convs.count.formatted()) rows with \(ConversationImport.pairCount(in: convs.flatMap { $0 }).formatted()) fine-tuning pairs")
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
            addCorpusSource(name: job.dataset.displayName, origin: "Hugging Face Viewer · \(job.dataset.id)", text: text)
            tokenizer = nil
        case .fineTune:
            let conversations = ConversationImport.conversations(from: rows)
            guard !conversations.isEmpty else {
                finishViewerImport(error: "This dataset doesn't expose recognized messages, instruction/output, or prompt/response columns.")
                return
            }
            addSFTSource(name: job.dataset.displayName, origin: "Hugging Face Viewer · \(job.dataset.id)", conversations: conversations)
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
                    self.addSFTSource(name: "iMessage chats", origin: "Local iMessage database", conversations: conversations)
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

    func addSFTSource(name: String, origin: String, conversations: [[ChatMessage]]) {
        sftSources.append(SFTDataSource(name: name, origin: origin, conversations: conversations))
        rebuildSFTMix()
    }

    func rebuildSFTMix() {
        let enabled = sftSources.filter(\.isEnabled)
        guard !enabled.isEmpty else {
            sftConversations = []
            sftDatasetName = "No fine-tuning data selected"
            return
        }
        var merged: [[ChatMessage]] = []
        for source in enabled {
            let available = source.conversations.count
            let count: Int
            switch source.limitMode {
            case .lines: count = min(available, max(0, source.lineLimit))
            case .percent: count = min(available, max(1, Int((Double(available) * source.percent / 100).rounded())))
            }
            merged.append(contentsOf: source.conversations.prefix(count))
        }
        sftConversations = merged
        sftDatasetName = enabled.count == 1 ? enabled[0].name : "Merged \(enabled.count) datasets"
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
