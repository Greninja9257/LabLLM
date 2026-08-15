import SwiftUI

enum NavSection: String, CaseIterable, Identifiable {
    case welcome = "Welcome"
    case model = "Model Builder"
    case dataset = "Dataset"
    case recipes = "Recipes"
    case fineTuneData = "Fine-tune Data"
    case training = "Training"
    case sampling = "Sampling"
    case chat = "Chat"
    case xray = "X-Ray"
    case embeddings = "Embeddings"
    case checkpoints = "Models"
    case server = "Local Server"
    case estimator = "Estimator"
    case hardware = "Hardware"
    case roadmap = "Roadmap"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .welcome: return "house.fill"
        case .model: return "cube.transparent"
        case .dataset: return "text.book.closed"
        case .recipes: return "wand.and.stars"
        case .fineTuneData: return "tray.full"
        case .training: return "waveform.path.ecg"
        case .sampling: return "text.cursor"
        case .chat: return "bubble.left.and.bubble.right"
        case .xray: return "eye"
        case .embeddings: return "point.3.connected.trianglepath.dotted"
        case .checkpoints: return "cube.box"
        case .server: return "server.rack"
        case .estimator: return "function"
        case .hardware: return "cpu"
        case .roadmap: return "map"
        case .settings: return "gearshape"
        }
    }
    var iconColor: Color {
        switch self {
        case .welcome: return Color(red: 0.22, green: 0.68, blue: 0.52)
        case .model: return Color(red: 0.36, green: 0.48, blue: 0.96)
        case .dataset: return Color(red: 0.92, green: 0.55, blue: 0.20)
        case .recipes: return Color(red: 0.72, green: 0.40, blue: 0.90)
        case .fineTuneData: return Color(red: 0.91, green: 0.36, blue: 0.54)
        case .training: return Color(red: 0.18, green: 0.70, blue: 0.51)
        case .sampling: return Color(red: 0.20, green: 0.62, blue: 0.80)
        case .chat: return Color(red: 0.34, green: 0.66, blue: 0.83)
        case .checkpoints: return Color(red: 0.69, green: 0.52, blue: 0.22)
        case .xray: return Color(red: 0.94, green: 0.40, blue: 0.30)
        case .embeddings: return Color(red: 0.40, green: 0.56, blue: 0.92)
        case .estimator: return Color(red: 0.55, green: 0.61, blue: 0.74)
        case .hardware: return Color(red: 0.46, green: 0.70, blue: 0.60)
        case .server: return Color(red: 0.34, green: 0.63, blue: 0.82)
        case .roadmap: return Color(red: 0.78, green: 0.51, blue: 0.32)
        case .settings: return Color(red: 0.54, green: 0.58, blue: 0.66)
        }
    }
    var group: String {
        switch self {
        case .welcome: return "HOME"
        case .model, .dataset, .recipes, .fineTuneData: return "BUILD"
        case .training, .sampling, .chat, .checkpoints: return "RUN"
        case .xray, .embeddings, .estimator, .hardware: return "ANALYZE"
        case .server, .roadmap, .settings: return "SYSTEM"
        }
    }
    /// Modes change presentation and controls. Core creation workflows stay available
    /// to beginners; analysis and serving remain deliberately expert-oriented.
    var minMode: AppMode {
        switch self {
        case .welcome, .model, .dataset, .training, .sampling, .chat, .settings, .fineTuneData: return .simple
        case .recipes, .checkpoints, .estimator, .hardware: return .advanced
        case .xray, .embeddings, .server, .roadmap: return .expert
        }
    }
}

/// Top-level view: gates onboarding, hosts the loading overlay, and shows the app.
struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var loading: LoadingState
    @EnvironmentObject var tutorial: TutorialState
    @State private var showWelcome = false

    var body: some View {
        ContentView(showTutorial: { tutorial.restart() },
                    showWelcome: { showWelcome = true })
        // Each full-window surface is conditionally created. Keeping an empty ZStack
        // sibling above the workspace can still interfere with AppKit hit testing.
        .overlay {
            if loading.isLoading {
                LoadingOverlay(state: loading)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if state.dataImport.isRunning {
                DataImportProgressPanel(state: state.dataImport, cancel: state.cancelActiveDataImport)
                    .padding(20)
            }
        }
        .onAppear { if !prefs.hasOnboarded && prefs.autoShowWelcome { showWelcome = true } }
        .sheet(isPresented: $showWelcome) {
            WelcomeView { showWelcome = false }
                .environmentObject(prefs)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWelcome)) { _ in showWelcome = true }
        .onReceive(NotificationCenter.default.publisher(for: .showTutorial)) { _ in tutorial.restart() }
        .tint(prefs.accent.color)
        .groupBoxStyle(WorkbenchGroupBoxStyle())
        .overlayPreferenceValue(TutorialTargetKey.self) { targets in
            GeometryReader { proxy in
                if tutorial.isActive {
                    TutorialHighlightOverlay(highlight: tutorial.targetAction(from: targets).flatMap { targets[$0].map { proxy[$0] } })
                }
            }
            // GeometryReader fills the whole window even when its conditional child is empty.
            // It must never participate in input dispatch; the coach card is a separate overlay.
            .allowsHitTesting(false)
        }
        .overlayPreferenceValue(TutorialTargetKey.self) { targets in
            GeometryReader { proxy in
                if tutorial.isActive {
                    let target = tutorial.targetAction(from: targets).flatMap { targets[$0].map { proxy[$0] } }
                    TutorialCoachCard(state: tutorial)
                        .frame(width: 380)
                        .position(tutorialCoachPosition(for: target, in: proxy.size))
                }
            }
        }
    }

    private func tutorialCoachPosition(for target: CGRect?, in size: CGSize) -> CGPoint {
        let cardSize = CGSize(width: 380, height: 320)
        let margin: CGFloat = 24
        let fallback = CGPoint(x: size.width - cardSize.width / 2 - margin,
                               y: size.height - cardSize.height / 2 - margin)
        guard let target else { return fallback }

        let candidates = [
            CGPoint(x: target.midX, y: target.maxY + margin + cardSize.height / 2),
            CGPoint(x: target.midX, y: target.minY - margin - cardSize.height / 2),
            CGPoint(x: target.maxX + margin + cardSize.width / 2, y: target.midY),
            CGPoint(x: target.minX - margin - cardSize.width / 2, y: target.midY)
        ]

        let fitting = candidates.first { point in
            point.x - cardSize.width / 2 >= margin && point.x + cardSize.width / 2 <= size.width - margin &&
            point.y - cardSize.height / 2 >= margin && point.y + cardSize.height / 2 <= size.height - margin
        }
        let preferred = fitting ?? candidates[0]
        return CGPoint(
            x: min(max(preferred.x, cardSize.width / 2 + margin), size.width - cardSize.width / 2 - margin),
            y: min(max(preferred.y, cardSize.height / 2 + margin), size.height - cardSize.height / 2 - margin))
    }
}

extension Notification.Name {
    static let navigateToSection = Notification.Name("LabLLM.navigateToSection")
    static let prepareTrainingContinuation = Notification.Name("LabLLM.prepareTrainingContinuation")
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var trainer: Trainer
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var tutorial: TutorialState
    var showTutorial: () -> Void
    var showWelcome: () -> Void

    @State private var selection: NavSection? = .welcome

    private var visibleNavSections: [NavSection] {
        NavSection.allCases.filter { section in
            section == .settings ||
            (prefs.isNavigationSectionVisible(section.rawValue) &&
             (!prefs.respectModeFeatureGates || prefs.unlocked(section.minMode)))
        }
    }

    private var navigationGroups: [String] { ["HOME", "BUILD", "RUN", "ANALYZE", "SYSTEM"] }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WorkbenchTheme.elevatedPanel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .automatic) { modeBadge }
            ToolbarItem(placement: .automatic) {
                Button { showTutorial() } label: { Image(systemName: "questionmark.circle") }
                    .help("Replay tutorial")
            }
        }
        .onChange(of: prefs.mode) { _ in
            if let sel = selection, !visibleNavSections.contains(sel) { selection = visibleNavSections.first ?? .settings }
        }
        .onChange(of: prefs.respectModeFeatureGates) { _ in
            if let sel = selection, !visibleNavSections.contains(sel) { selection = visibleNavSections.first ?? .settings }
        }
        .onChange(of: selection) { newValue in
            if let newValue { tutorial.noteNavigation(to: newValue) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { note in
            guard let raw = note.object as? String, let section = NavSection(rawValue: raw) else { return }
            selection = section
            tutorial.noteNavigation(to: section)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile").foregroundStyle(WorkbenchTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LABLLM").font(.caption.weight(.bold)).foregroundStyle(WorkbenchTheme.accent)
                    Text("Local model studio").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(navigationGroups, id: \.self) { group in
                        let sections = visibleNavSections.filter { $0.group == group }
                        if !sections.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                if prefs.showSidebarGroups {
                                    Text(group).font(.caption2.weight(.bold)).foregroundStyle(.secondary).padding(.horizontal, 16)
                                }
                                ForEach(sections) { section in
                                    let tutorialAction = tutorial.navigationTarget(for: section)
                                    Button {
                                        selection = section
                                        tutorial.noteNavigation(to: section)
                                    } label: {
                                        HStack(spacing: 9) {
                                            Image(systemName: section.icon)
                                                .foregroundStyle(selection == section ? Color.white : section.iconColor)
                                                .frame(width: 16)
                                            Text(section.rawValue).lineLimit(1).foregroundStyle(selection == section ? Color.white : Color.primary)
                                            Spacer(minLength: 0)
                                        }
                                        .font(.callout.weight(selection == section ? .semibold : .regular))
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(selection == section ? WorkbenchTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity)
                                    .tutorialTarget(tutorialAction ?? .idle)
                                }
                            }
                        }
                    }
                }.padding(.bottom, 12)
            }
            if prefs.showTrainingStatusBadge {
                trainingBadge
            }
        }
        .frame(width: prefs.sidebarWidth)
        .background(WorkbenchTheme.panel)
    }

    @ViewBuilder private var detail: some View {
        switch selection ?? .model {
        case .welcome: WelcomeHomeView()
        case .model: ModelBuilderView()
        case .dataset: DatasetView()
        case .recipes: RecipesView()
        case .fineTuneData: FineTuneDataView()
        case .training: TrainingView()
        case .sampling: SamplingView()
        case .chat: ChatView()
        case .xray: XRayView()
        case .embeddings: EmbeddingsView()
        case .checkpoints: CheckpointsView()
        case .server: ServerView()
        case .estimator: EstimatorView()
        case .hardware: HardwareView()
        case .roadmap: RoadmapView()
        case .settings: SettingsView(showTutorial: showTutorial, showWelcome: showWelcome)
        }
    }

    private var modeBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: prefs.mode.icon).font(.caption)
            Text(prefs.mode.label + " mode").font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(WorkbenchTheme.accent.opacity(0.12), in: Capsule())
    }

    @ViewBuilder private var trainingBadge: some View {
        if trainer.isTraining {
            HStack(spacing: 8) {
                ProgressView(value: trainer.progress).controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Int((trainer.progress * 100).rounded()))% · Step \(trainer.step)/\(trainer.maxSteps)").font(.caption).monospacedDigit()
                    Text(String(format: "loss %.3f", trainer.trainLoss))
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
            }
            .padding(10)
            .background(.thinMaterial)
        }
    }
}
