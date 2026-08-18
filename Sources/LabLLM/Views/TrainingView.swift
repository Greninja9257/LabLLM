import SwiftUI
import Charts

struct TrainingView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var library: DatasetLibrary
    @EnvironmentObject var trainer: Trainer
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var tutorial: TutorialState
    @State private var mode: RunMode = .pretrain
    @State private var useLoRA = true
    @State private var resumeFrom: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkbenchPageHeader(eyebrow: "Run Studio", title: "Training", subtitle: "Configure the run, watch learning happen, and compare training against validation loss.", icon: "waveform.path.ecg")
                HStack(spacing: 12) {
                    Picker("", selection: $mode) {
                        ForEach(RunMode.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).frame(maxWidth: 420)
                    Spacer()
                    // Recipes are reachable from the page where runs actually start.
                    Menu {
                        ForEach(Recipe.all.filter { $0.mode == mode }) { recipe in
                            Button("\(recipe.name) · \(recipe.timeTag)") { state.run(recipe, inNewModel: false) }
                        }
                        Divider()
                        Button("Open Recipes…") {
                            NotificationCenter.default.post(name: .navigateToSection, object: NavSection.recipes.rawValue)
                        }
                    } label: { Label("Start from a recipe", systemImage: "wand.and.stars") }
                        .menuStyle(.borderlessButton).frame(width: 190)
                        .disabled(trainer.isTraining)
                }

                if let err = trainer.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).padding(10)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius))
                }
                modeTip
                restoredSessionPanel
                trainingDataPanel
                controlsPanel
                runProgressPanel
                metricsPanel
                chartPanel
                sampleTimeline
            }
            .padding(WorkbenchTheme.pagePadding)
        }
        .onAppear {
            // Open on the mode whose saved run is showing, so a relaunch lands on
            // the dashboard the user left behind.
            if !trainer.isTraining { mode = trainer.runMode }
            applyPendingContinuation()
        }
        .onChange(of: mode) { newMode in state.showSession(for: newMode) }
        .onReceive(NotificationCenter.default.publisher(for: .prepareTrainingContinuation)) { note in
            mode = note.object as? String == "sft" ? .sft : .pretrain
            applyPendingContinuation()
        }
    }

    @ViewBuilder private var modeTip: some View {
        switch mode {
        case .pretrain:
            if prefs.mode == .simple && prefs.showTips {
                tip("Choose the corpora this run trains on above, then press Start. Watch the loss fall — lower is better. A checkpoint saves periodically and again when the run finishes or is stopped.")
            }
        case .sft:
            tip("Fine-tuning continues from your pretrained (or resumed) model and trains only on the assistant's replies. LoRA trains a small adapter instead of the whole model — faster and swappable.")
        case .dpo:
            tip("DPO needs a fine-tuned model already in memory (run Fine-tune first, or resume from an SFT checkpoint). It nudges the model toward the 'chosen' replies and away from 'rejected' ones.")
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb").foregroundStyle(.yellow)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.10), in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
    }


    /// Shown when the metrics on screen come from a saved run rather than a live
    /// one, with a one-click way back into that run's checkpoint.
    @ViewBuilder private var restoredSessionPanel: some View {
        if !trainer.isTraining, let session = state.session(for: mode), session.step > 0 {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(WorkbenchTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Restored session · \(session.summary)").font(.callout.weight(.medium))
                    Text("Saved \(session.updatedAt.formatted(date: .abbreviated, time: .shortened))\(session.datasetName.map { " · \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let url = session.lastCheckpointURL, FileManager.default.fileExists(atPath: url.path) {
                    Button(trainer.hasModel ? "Reload checkpoint" : "Load model from this run") {
                        if let meta = try? Checkpoint.loadMeta(from: url) { state.loadCheckpoint(url, meta: meta) }
                    }.buttonStyle(WorkbenchSecondaryButtonStyle())
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkbenchTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        }
    }

    // MARK: - Training data

    /// Dataset selection and mixing live with the run, not with the dataset
    /// browsers: the browsers install data, this panel decides what a run uses.
    @ViewBuilder private var trainingDataPanel: some View {
        switch mode {
        case .pretrain: mixPanel(kind: .corpus)
        case .sft: mixPanel(kind: .fineTune)
        case .dpo:
            GroupBox("Training data") {
                Text("DPO reuses the preference pairs loaded for the current model. Run fine-tuning first, or resume from an SFT checkpoint.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }
    }

    private func mixPanel(kind: InstalledDataset.Kind) -> some View {
        let mix = kind == .corpus ? state.corpusMix : state.fineTuneMix
        let installed = library.datasets(of: kind)
        let unused = installed.filter { dataset in !mix.contains { $0.datasetID == dataset.id } }
        return GroupBox(kind == .corpus ? "Training data · pre-training corpora" : "Training data · fine-tuning datasets") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind == .corpus ? state.corpusName : state.sftDatasetName)
                            .font(.headline)
                        Text(mixSummary(kind: kind)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                    if state.isLoadingMix { ProgressView().controlSize(.small) }
                    Menu {
                        if unused.isEmpty {
                            Text("Everything installed is already in this mix")
                        } else {
                            ForEach(unused) { dataset in
                                Button("\(dataset.name) · \(dataset.summary)") { state.addToMix(dataset) }
                            }
                        }
                    } label: { Label("Add dataset", systemImage: "plus") }
                        .menuStyle(.borderlessButton).frame(width: 130)
                    Button("Install more…") {
                        NotificationCenter.default.post(name: .navigateToSection,
                                                        object: kind == .corpus ? NavSection.dataset.rawValue : NavSection.fineTuneData.rawValue)
                    }.buttonStyle(WorkbenchSecondaryButtonStyle())
                }

                if mix.isEmpty {
                    Text(installed.isEmpty
                         ? "No \(kind == .corpus ? "pre-training" : "fine-tuning") data is installed yet. Install a dataset and it stays on disk for future sessions."
                         : "Nothing selected for this run yet. Add one or more installed datasets to build the mix.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(mix) { selection in
                        if let dataset = library.dataset(selection.datasetID) {
                            DatasetMixRow(dataset: dataset,
                                          selection: selection,
                                          onToggle: { state.setMixEnabled($0, for: dataset.id, kind: kind) },
                                          onMode: { state.setMixLimitMode($0, for: dataset.id, kind: kind) },
                                          onPercent: { state.setMixPercent($0, for: dataset.id, kind: kind) },
                                          onLines: { state.setMixLineLimit($0, for: dataset.id, kind: kind) },
                                          onRemove: { state.removeFromMix(dataset.id, kind: kind) })
                        }
                    }
                }
            }.padding(8)
        }
    }

    private func mixSummary(kind: InstalledDataset.Kind) -> String {
        switch kind {
        case .corpus:
            let suffix = state.isCorpusLoaded ? "loaded" : "read when the run starts"
            return "\(state.corpusCharCount.formatted()) characters · \(suffix)"
        case .fineTune:
            let suffix = state.isFineTuneDataLoaded ? "loaded" : "read when the run starts"
            return "\(state.sftRowCount.formatted()) rows · \(state.sftPairCount.formatted()) pairs · \(suffix)"
        }
    }

    private var controlsPanel: some View {
        GroupBox("Hyperparameters") {
            VStack(spacing: 12) {
                if mode == .sft {
                    Toggle("Use LoRA (train a small adapter instead of full fine-tuning)", isOn: $useLoRA)
                }
                if prefs.mode != .simple {
                    HStack {
                        Text("Optimizer").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $state.trainConfig.optimizer) {
                            ForEach(OptimizerKind.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).frame(width: 200)
                        Spacer()
                        resumeMenu
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    intField("Batch size", $state.trainConfig.batchSize)
                    intField("Max steps", $state.trainConfig.maxSteps)
                    floatField("Learning rate", $state.trainConfig.learningRate)
                    intField("Warmup steps", $state.trainConfig.warmupSteps)
                    if prefs.mode != .simple {
                        intField("Grad accum", $state.trainConfig.gradAccumSteps)
                        floatField("Weight decay", $state.trainConfig.weightDecay)
                        floatField("Grad clip", $state.trainConfig.gradClip)
                        intField("Checkpoint every", $state.trainConfig.checkpointEvery)
                    }
                    if mode == .pretrain && prefs.mode != .simple { intField("Eval every", $state.trainConfig.evalEvery) }
                    if mode == .sft && useLoRA && prefs.mode == .expert {
                        intField("LoRA rank", $state.trainConfig.loraRank)
                        floatField("LoRA alpha", $state.trainConfig.loraAlpha)
                    }
                    if mode == .dpo { floatField("DPO beta", $state.trainConfig.dpoBeta) }
                    if prefs.mode == .expert { intField("Sample every", $state.trainConfig.sampleEvery) }
                }
                HStack(spacing: 12) {
                    if !trainer.isTraining {
                        Button(action: startTapped) {
                            Label(startLabel, systemImage: "play.fill")
                        }
                        .buttonStyle(WorkbenchPrimaryButtonStyle())
                        .disabled(startDisabled)
                        .tutorialTarget(mode == .sft ? .fineTuneStarted : .trainingStarted)
                    } else {
                        if trainer.isPaused {
                            Button { trainer.resume() } label: { Label("Resume", systemImage: "play.fill") }
                                .buttonStyle(WorkbenchPrimaryButtonStyle())
                        } else {
                            Button { trainer.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                                .buttonStyle(WorkbenchSecondaryButtonStyle())
                        }
                        Button(role: .destructive) { trainer.stop() } label: {
                            Label("Stop (saves progress)", systemImage: "stop.fill")
                        }.buttonStyle(WorkbenchSecondaryButtonStyle())
                    }
                    Spacer()
                    Text(trainer.statusMessage).foregroundStyle(.secondary).font(.callout)
                }
            }.padding(8)
        }
    }

    private var resumeMenu: some View {
        Menu {
            Button("Start fresh") { resumeFrom = nil }
            Divider()
            ForEach(Checkpoint.list(), id: \.self) { url in
                Button(url.lastPathComponent) { resumeFrom = url }
            }
        } label: {
            Label(resumeFrom?.lastPathComponent ?? "Resume from checkpoint…", systemImage: "arrow.uturn.backward")
        }.menuStyle(.borderlessButton).frame(maxWidth: 260)
    }

    private var startDisabled: Bool {
        switch mode {
        case .pretrain: return !state.gptConfig.validationErrors.isEmpty || !state.hasCorpus
        case .sft: return !state.hasFineTuneData
        case .dpo: return false
        }
    }

    private var startLabel: String {
        switch mode {
        case .pretrain: return "Start training"
        case .sft: return "Start fine-tuning"
        case .dpo: return "Start DPO"
        }
    }

    private func startTapped() {
        if mode == .pretrain { tutorial.complete(.trainingStarted) }
        if mode == .sft { tutorial.complete(.fineTuneStarted) }
        switch mode {
        case .pretrain: state.startTraining(resumeFrom: resumeFrom)
        case .sft: state.startSFT(useLoRA: useLoRA, resumeFrom: resumeFrom)
        case .dpo: state.startDPO()
        }
    }

    private func applyPendingContinuation() {
        guard let request = state.pendingContinuation else { return }
        resumeFrom = request.url
        state.gptConfig = request.meta.config
        state.tokenizer = request.meta.tokenizer
    }

    private var metricsPanel: some View {
        GroupBox {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                WorkbenchMetric(label: "Step", value: "\(trainer.step)/\(trainer.maxSteps)")
                WorkbenchMetric(label: "Progress", value: "\(Int((trainer.progress * 100).rounded()))%", tone: WorkbenchTheme.accent)
                WorkbenchMetric(label: "Train loss", value: String(format: "%.3f", trainer.trainLoss), tone: WorkbenchTheme.accent)
                WorkbenchMetric(label: "Val loss", value: trainer.valLoss > 0 ? String(format: "%.3f", trainer.valLoss) : "—", tone: WorkbenchTheme.validation)
                WorkbenchMetric(label: "Perplexity", value: trainer.trainLoss > 0 ? String(format: "%.1f", exp(trainer.trainLoss)) : "—")
                WorkbenchMetric(label: "Tokens / sec", value: String(format: "%.0f", trainer.tokensPerSec))
                WorkbenchMetric(label: "Learning rate", value: String(format: "%.2e", trainer.currentLR))
                WorkbenchMetric(label: "ETA", value: formatETA(trainer.etaSeconds))
                if trainer.runIsLoRA { WorkbenchMetric(label: "Training mode", value: "LoRA", tone: WorkbenchTheme.accent) }
            }
        }
    }

    @ViewBuilder private var runProgressPanel: some View {
        if trainer.isTraining || trainer.step > 0 {
            GroupBox("Run progress") {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: trainer.progress)
                        .tint(WorkbenchTheme.accent)
                    HStack {
                        Text("\(Int((trainer.progress * 100).rounded()))% complete")
                            .font(.callout.weight(.semibold)).monospacedDigit()
                        Spacer()
                        Text("Step \(trainer.step.formatted()) of \(trainer.maxSteps.formatted())")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }
        }
    }

    private var chartPanel: some View {
        GroupBox("Loss") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Label("Training loss", systemImage: "line.diagonal").foregroundStyle(.tint)
                    Label("Validation loss", systemImage: "line.diagonal").foregroundStyle(WorkbenchTheme.validation)
                }.font(.caption)
                Chart {
                    ForEach(trainer.lossHistory.filter { $0.kind == .train }) { point in
                        LineMark(x: .value("Step", point.step), y: .value("Loss", point.value), series: .value("Series", "Training"))
                            .foregroundStyle(WorkbenchTheme.accent)
                            .interpolationMethod(.linear)
                    }
                    ForEach(trainer.lossHistory.filter { $0.kind == .val }) { point in
                        LineMark(x: .value("Step", point.step), y: .value("Loss", point.value), series: .value("Series", "Validation"))
                            .foregroundStyle(WorkbenchTheme.validation)
                            .interpolationMethod(.linear)
                    }
                }
                .frame(height: 236)
            }
            .padding(8)
        }
    }

    @ViewBuilder private var sampleTimeline: some View {
        if !trainer.sampleHistory.isEmpty {
            GroupBox("Sample timeline") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(trainer.sampleHistory.reversed()) { sample in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 3) {
                                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                                Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1, height: 42)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Step \(sample.step) · \(sample.method)").font(.caption.bold()).foregroundStyle(.secondary)
                                Text(sample.text).font(.callout.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                }.padding(8)
            }
        }
    }

    private func intField(_ label: String, _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number).textFieldStyle(.roundedBorder)
        }
    }
    private func floatField(_ label: String, _ value: Binding<Float>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number).textFieldStyle(.roundedBorder)
        }
    }
    private func formatETA(_ s: Double) -> String {
        guard s > 0, s.isFinite else { return "—" }
        let m = Int(s) / 60, sec = Int(s) % 60
        return m > 0 ? "\(m)m \(sec)s" : "\(sec)s"
    }
}


/// One installed dataset's share of a run. Percentage and row limits are committed
/// when the control is released so dragging a slider doesn't re-read files on every
/// intermediate value.
private struct DatasetMixRow: View {
    let dataset: InstalledDataset
    let selection: DatasetSelection
    let onToggle: (Bool) -> Void
    let onMode: (DatasetLimitMode) -> Void
    let onPercent: (Double) -> Void
    let onLines: (Int) -> Void
    let onRemove: () -> Void

    @State private var draftPercent: Double = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(dataset.name, isOn: Binding(get: { selection.isEnabled }, set: onToggle))
                    .toggleStyle(.checkbox)
                Spacer()
                Text(selectedSummary).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button(role: .destructive) { onRemove() } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain).help("Remove from this model's mix (keeps it installed)")
            }
            Text(dataset.origin).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Picker("Selection", selection: Binding(get: { selection.limitMode }, set: onMode)) {
                ForEach(DatasetLimitMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            if selection.limitMode == .percent {
                HStack {
                    Slider(value: $draftPercent, in: 1...100, step: 1) { editing in
                        if !editing { onPercent(draftPercent) }
                    }
                    Text("\(Int(draftPercent))%").font(.caption.monospacedDigit()).frame(width: 42)
                }
            } else {
                Stepper("\(selection.lineLimit.formatted()) \(dataset.kind == .corpus ? "lines" : "rows")",
                        value: Binding(get: { selection.lineLimit }, set: onLines),
                        in: 1...max(1, dataset.rows))
            }
        }
        .padding(10)
        .opacity(selection.isEnabled ? 1 : 0.55)
        .background(WorkbenchTheme.elevatedPanel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        .onAppear { draftPercent = selection.percent }
        .onChange(of: selection.percent) { draftPercent = $0 }
    }

    private var selectedSummary: String {
        switch dataset.kind {
        case .corpus:
            return "\(selection.selectedCharacters(in: dataset).formatted()) of \(dataset.characters.formatted()) characters"
        case .fineTune:
            return "\(selection.selectedRows(in: dataset).formatted()) of \(dataset.rows.formatted()) rows · \(selection.selectedPairs(in: dataset).formatted()) pairs"
        }
    }
}
