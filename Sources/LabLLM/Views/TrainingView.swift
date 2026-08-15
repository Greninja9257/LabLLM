import SwiftUI
import Charts

private enum TrainMode: String, CaseIterable { case pretrain = "Pretrain", sft = "Fine-tune (chat)", dpo = "DPO" }

struct TrainingView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var trainer: Trainer
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var tutorial: TutorialState
    @State private var mode: TrainMode = .pretrain
    @State private var useLoRA = true
    @State private var resumeFrom: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkbenchPageHeader(eyebrow: "Run Studio", title: "Training", subtitle: "Configure the run, watch learning happen, and compare training against validation loss.", icon: "waveform.path.ecg")
                Picker("", selection: $mode) {
                    ForEach(TrainMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 420)

                if let err = trainer.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).padding(10)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius))
                }
                modeTip
                controlsPanel
                runProgressPanel
                metricsPanel
                chartPanel
                sampleTimeline
            }
            .padding(WorkbenchTheme.pagePadding)
        }
        .onAppear(perform: applyPendingContinuation)
        .onReceive(NotificationCenter.default.publisher(for: .prepareTrainingContinuation)) { note in
            mode = note.object as? String == "sft" ? .sft : .pretrain
            applyPendingContinuation()
        }
    }

    @ViewBuilder private var modeTip: some View {
        switch mode {
        case .pretrain:
            if prefs.mode == .simple && prefs.showTips {
                tip("Press Start. Watch the loss fall — lower is better. A checkpoint saves periodically and again when the run finishes or is stopped.")
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
                        .disabled(mode == .pretrain && !state.gptConfig.validationErrors.isEmpty)
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
