import Foundation
import SwiftUI

enum TutorialAction: String {
    case modelPreset, corpusAdded, trainingStarted, sampleGenerated, fineTuneSourceAdded
}

@MainActor
final class TutorialState: ObservableObject {
    @Published var isActive = false
    @Published private(set) var step = 0

    struct Step { let title: String; let message: String; let section: NavSection; let action: TutorialAction }
    let steps: [Step] = [
        .init(title: "Choose a starting model", message: "Select the Tiny profile to create a first model you can train quickly.", section: .model, action: .modelPreset),
        .init(title: "Add your training corpus", message: "Choose a text dataset on the left, then use Import corpus in the inspector.", section: .dataset, action: .corpusAdded),
        .init(title: "Start the run", message: "Open Training and start a pretraining run. LabLLM builds the tokenizer automatically in Simple mode.", section: .training, action: .trainingStarted),
        .init(title: "Generate from the model", message: "Open Sampling, enter a prompt, and generate a continuation.", section: .sampling, action: .sampleGenerated),
        .init(title: "Add fine-tuning data", message: "Browse a JSONL dataset and add it to your fine-tuning mix.", section: .fineTuneData, action: .fineTuneSourceAdded)
    ]

    var current: Step? { steps.indices.contains(step) ? steps[step] : nil }

    func start() { step = 0; isActive = true; navigate() }
    func complete(_ action: TutorialAction) {
        guard current?.action == action else { return }
        if step == steps.count - 1 { isActive = false } else { step += 1; navigate() }
    }
    func dismiss() { isActive = false }
    private func navigate() { if let current { NotificationCenter.default.post(name: .navigateToSection, object: current.section.rawValue) } }
}

struct TutorialCoachOverlay: View {
    @ObservedObject var state: TutorialState
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.58).ignoresSafeArea().allowsHitTesting(false)
            if let step = state.current {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("GUIDED SETUP \(state.step + 1) OF \(state.steps.count)").font(.caption.weight(.bold)).foregroundStyle(WorkbenchTheme.accent)
                        Spacer()
                        Button { state.dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Exit tutorial")
                    }
                    Text(step.title).font(.title3.bold())
                    Text(step.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack { Image(systemName: "cursorarrow.click").foregroundStyle(WorkbenchTheme.accent); Text("Complete the highlighted task in the workspace to continue.").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(18).frame(width: 360, alignment: .leading)
                .background(WorkbenchTheme.elevatedPanel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(WorkbenchTheme.accent.opacity(0.35)) }
                .padding(24)
            }
        }
    }
}
