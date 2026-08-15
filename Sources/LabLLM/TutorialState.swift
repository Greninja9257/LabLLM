import Foundation
import SwiftUI

enum TutorialAction: String {
    case idle, sectionNav, welcomeOpened, modelPreset, corpusAdded, trainingStarted, sampleGenerated, chatOpened, fineTuneSourceAdded, fineTuneStarted
    case openSettingsForAdvanced, enableAdvanced, recipesOpened, modelsOpened, estimatorOpened, hardwareOpened
    case openSettingsForExpert, enableExpert, xrayOpened, embeddingsOpened, serverOpened, roadmapOpened
}

@MainActor
final class TutorialState: ObservableObject {
    enum StepKind {
        case visit
        case task
        case mode(AppMode)
    }

    private enum StorageKey {
        static let step = "labllm.tutorial.step"
        static let currentStepComplete = "labllm.tutorial.currentStepComplete"
        static let hasStarted = "labllm.tutorial.hasStarted"
    }

    @Published var isActive = false
    @Published private(set) var step: Int
    @Published private(set) var isCurrentStepComplete: Bool
    struct Step {
        let phase: String
        let title: String
        let message: String
        let section: NavSection
        let action: TutorialAction
        let kind: StepKind
        let checkpoint: String
    }
    let steps: [Step] = [
        .init(phase: "Start", title: "Enter the workspace", message: "Begin at Welcome so the app starts from the real workflow, not a disconnected help screen.", section: .welcome, action: .welcomeOpened, kind: .visit, checkpoint: "Welcome page opened"),
        .init(phase: "Simple", title: "Choose a starting model", message: "Choose any profile that fits the experiment. Tiny is fast; larger profiles are for bigger datasets and more memory.", section: .model, action: .modelPreset, kind: .task, checkpoint: "Model profile chosen"),
        .init(phase: "Simple", title: "Add pre-training data", message: "Search or choose a recommended corpus, inspect the dataset card, then import the actual data file.", section: .dataset, action: .corpusAdded, kind: .task, checkpoint: "Corpus imported"),
        .init(phase: "Simple", title: "Start pretraining", message: "Start a small run first. Simple mode automatically builds the tokenizer when training begins.", section: .training, action: .trainingStarted, kind: .task, checkpoint: "Training started"),
        .init(phase: "Simple", title: "Watch learning", message: "Use the Training page to compare blue training loss against orange validation loss and review generated samples in the timeline.", section: .training, action: .trainingStarted, kind: .visit, checkpoint: "Training dashboard reviewed"),
        .init(phase: "Simple", title: "Generate text", message: "Open Sampling, adjust generation settings if needed, then generate or continue inside the prompt surface.", section: .sampling, action: .sampleGenerated, kind: .task, checkpoint: "Sample generated"),
        .init(phase: "Simple", title: "Try local chat", message: "Use Chat once a model or checkpoint is loaded. This keeps conversation testing in the same local project.", section: .chat, action: .chatOpened, kind: .visit, checkpoint: "Chat opened"),
        .init(phase: "Simple", title: "Add fine-tuning data", message: "Browse instruction or conversation datasets, inspect the rendered README, then add compatible rows to the fine-tuning mix.", section: .fineTuneData, action: .fineTuneSourceAdded, kind: .task, checkpoint: "Fine-tuning rows imported"),
        .init(phase: "Simple", title: "Start fine-tuning", message: "Return to Training, choose Fine-tune, and run a tiny SFT pass before scaling up.", section: .training, action: .fineTuneStarted, kind: .task, checkpoint: "Fine-tuning started"),
        .init(phase: "Advanced", title: "Open Settings", message: "Mode changes are explicit. Open Settings when you want additional controls; the guide will not switch modes by itself.", section: .settings, action: .openSettingsForAdvanced, kind: .visit, checkpoint: "Settings opened"),
        .init(phase: "Advanced", title: "Enable Advanced mode", message: "Choose Advanced to reveal recipes, model management, hardware, and planning tools.", section: .settings, action: .enableAdvanced, kind: .mode(.advanced), checkpoint: "Advanced mode enabled"),
        .init(phase: "Advanced", title: "Use a recipe", message: "Open Recipes to apply a focused configuration before a run.", section: .recipes, action: .recipesOpened, kind: .visit, checkpoint: "Recipes opened"),
        .init(phase: "Advanced", title: "Manage models", message: "Open Models to load checkpoints, continue training or fine-tuning, and organize saved runs.", section: .checkpoints, action: .modelsOpened, kind: .visit, checkpoint: "Models opened"),
        .init(phase: "Advanced", title: "Estimate resources", message: "Open Estimator before a bigger experiment to check memory, disk, token budget, and rough time.", section: .estimator, action: .estimatorOpened, kind: .visit, checkpoint: "Estimator opened"),
        .init(phase: "Advanced", title: "Check hardware", message: "Open Hardware to compare your Apple Silicon and memory against recommended model sizes.", section: .hardware, action: .hardwareOpened, kind: .visit, checkpoint: "Hardware opened"),
        .init(phase: "Expert", title: "Return to Settings", message: "Expert mode reveals analysis, serving, and deeper inspection tools. Switch only when you want the full surface area.", section: .settings, action: .openSettingsForExpert, kind: .visit, checkpoint: "Settings reopened"),
        .init(phase: "Expert", title: "Enable Expert mode", message: "Choose Expert to unlock X-Ray, embeddings, local serving, and the full roadmap.", section: .settings, action: .enableExpert, kind: .mode(.expert), checkpoint: "Expert mode enabled"),
        .init(phase: "Expert", title: "Inspect generation", message: "Open X-Ray to review token probabilities, entropy, and sampling decisions.", section: .xray, action: .xrayOpened, kind: .visit, checkpoint: "X-Ray opened"),
        .init(phase: "Expert", title: "Explore embeddings", message: "Open Embeddings to inspect the learned token space and similarity structure.", section: .embeddings, action: .embeddingsOpened, kind: .visit, checkpoint: "Embeddings opened"),
        .init(phase: "Expert", title: "Serve locally", message: "Open Local Server to expose a loaded model through the local API and streaming endpoint.", section: .server, action: .serverOpened, kind: .visit, checkpoint: "Local server opened"),
        .init(phase: "Finish", title: "Review the roadmap", message: "Open Roadmap to see what is built, what is in progress, and what is planned next.", section: .roadmap, action: .roadmapOpened, kind: .visit, checkpoint: "Roadmap opened")
    ]
    init() {
        let storedStep = UserDefaults.standard.integer(forKey: StorageKey.step)
        step = min(max(0, storedStep), steps.count - 1)
        isCurrentStepComplete = UserDefaults.standard.bool(forKey: StorageKey.currentStepComplete)
    }

    var current: Step? { steps.indices.contains(step) ? steps[step] : nil }
    var progress: Double { Double(step + (isCurrentStepComplete ? 1 : 0)) / Double(steps.count) }
    var completedCount: Int { step + (isCurrentStepComplete ? 1 : 0) }

    /// Resume the guide without moving the user or replacing their current work.
    func resume() {
        isActive = true
        UserDefaults.standard.set(true, forKey: StorageKey.hasStarted)
    }

    /// Used only by the explicit Replay Tutorial commands.
    func restart() {
        step = 0
        isCurrentStepComplete = false
        isActive = true
        persistProgress()
    }

    func complete(_ action: TutorialAction) {
        guard current?.action == action else { return }
        isCurrentStepComplete = true
        persistProgress()
    }

    func navigationTarget(for section: NavSection) -> TutorialAction? {
        current?.section == section ? .sectionNav : nil
    }

    func noteNavigation(to section: NavSection) {
        guard let current, current.section == section else { return }
        switch current.kind {
        case .visit:
            complete(current.action)
        case .task, .mode:
            persistProgress()
        }
    }

    func modeAction(for mode: AppMode) -> TutorialAction? {
        guard let current else { return nil }
        switch current.kind {
        case .mode(let required) where required == mode:
            return current.action
        default: return nil
        }
    }

    func goToCurrentSection() {
        guard let current else { return }
        NotificationCenter.default.post(name: .navigateToSection, object: current.section.rawValue)
        noteNavigation(to: current.section)
    }

    func targetAction(from available: [TutorialAction: Anchor<CGRect>]) -> TutorialAction? {
        guard let current else { return nil }
        if available[current.action] != nil { return current.action }
        if available[.sectionNav] != nil { return .sectionNav }
        return nil
    }

    func advance() {
        guard isCurrentStepComplete else { return }
        if step == steps.count - 1 {
            isActive = false
        } else {
            step += 1
            isCurrentStepComplete = false
            persistProgress()
        }
    }

    func back() {
        guard step > 0 else { return }
        step -= 1
        isCurrentStepComplete = true
        persistProgress()
    }

    func skipStep() {
        isCurrentStepComplete = true
        advance()
    }

    func dismiss() { isActive = false }

    private func persistProgress() {
        UserDefaults.standard.set(step, forKey: StorageKey.step)
        UserDefaults.standard.set(isCurrentStepComplete, forKey: StorageKey.currentStepComplete)
        UserDefaults.standard.set(true, forKey: StorageKey.hasStarted)
    }
}

struct TutorialTargetKey: PreferenceKey {
    static var defaultValue: [TutorialAction: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TutorialAction: Anchor<CGRect>], nextValue: () -> [TutorialAction: Anchor<CGRect>]) { value.merge(nextValue(), uniquingKeysWith: { $1 }) }
}

extension View {
    func tutorialTarget(_ action: TutorialAction) -> some View {
        anchorPreference(key: TutorialTargetKey.self, value: .bounds) { [action: $0] }
    }
}

struct TutorialHighlightOverlay: View {
    let highlight: CGRect?

    var body: some View {
        GeometryReader { proxy in
            if let highlight {
                let target = highlight
                    .insetBy(dx: -10, dy: -10)
                    .intersection(CGRect(origin: .zero, size: proxy.size))

                // `highlight` is the target's preference anchor resolved into this
                // overlay's coordinate space. No sidebar or window-size constants.
                ZStack {
                    Color.black.opacity(0.32)
                    RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                        .frame(width: target.width, height: target.height)
                        .position(x: target.midX, y: target.midY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                    .strokeBorder(WorkbenchTheme.accent, lineWidth: 2)
                    .frame(width: target.width, height: target.height)
                    .position(x: target.midX, y: target.midY)
            }
        }
    }
}

struct TutorialCoachCard: View {
    @ObservedObject var state: TutorialState

    var body: some View {
        if let step = state.current {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(step.phase.uppercased()).font(.caption.weight(.bold)).foregroundStyle(WorkbenchTheme.accent)
                    Spacer()
                    Text("\(Int((state.progress * 100).rounded()))%").font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(.secondary)
                    Button { state.dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Exit tutorial")
                }
                ProgressView(value: state.progress).tint(WorkbenchTheme.accent)
                HStack(spacing: 8) {
                    Text("Step \(state.step + 1) of \(state.steps.count)").font(.caption).foregroundStyle(.secondary)
                    Text(step.section.rawValue).font(.caption.weight(.semibold)).foregroundStyle(WorkbenchTheme.accent)
                }
                Text(step.title).font(.title3.bold())
                Text(step.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button {
                        state.goToCurrentSection()
                    } label: {
                        Label("Go to \(step.section.rawValue)", systemImage: "arrow.turn.down.right")
                    }
                    .buttonStyle(WorkbenchSecondaryButtonStyle())
                    Spacer()
                }
                miniMap
                HStack {
                    Image(systemName: state.isCurrentStepComplete ? "checkmark.circle.fill" : "cursorarrow.click")
                        .foregroundStyle(state.isCurrentStepComplete ? WorkbenchTheme.success : WorkbenchTheme.accent)
                    Text(state.isCurrentStepComplete ? "\(step.checkpoint). Continue when you are ready." : "Waiting for: \(step.checkpoint).")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if state.step > 0 {
                        Button("Back") { state.back() }.buttonStyle(WorkbenchSecondaryButtonStyle())
                    }
                    if state.isCurrentStepComplete {
                        Button("Next") { state.advance() }.buttonStyle(WorkbenchPrimaryButtonStyle())
                    } else {
                        Button("Skip") { state.skipStep() }.buttonStyle(WorkbenchSecondaryButtonStyle())
                    }
                }
            }
            .padding(18).frame(width: 380, alignment: .leading)
            .background(WorkbenchTheme.elevatedPanel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous).strokeBorder(WorkbenchTheme.accent.opacity(0.35)) }
        }
    }

    private var miniMap: some View {
        HStack(spacing: 5) {
            ForEach(state.steps.indices, id: \.self) { index in
                let completed = index < state.step || (index == state.step && state.isCurrentStepComplete)
                let current = index == state.step
                Image(systemName: completed ? "checkmark.circle.fill" : (current ? "clock.fill" : "circle"))
                    .font(.caption2)
                    .foregroundStyle(completed ? WorkbenchTheme.success : (current ? WorkbenchTheme.accent : Color.secondary.opacity(0.55)))
            }
        }
        .accessibilityLabel("\(state.completedCount) of \(state.steps.count) tutorial steps complete")
    }
}
