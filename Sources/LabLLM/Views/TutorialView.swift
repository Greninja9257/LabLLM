import SwiftUI

/// A hands-on checklist: each step routes to the actual workspace and updates
/// when the learner completes the relevant action.
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var state: AppState
    @EnvironmentObject var trainer: Trainer
    @State private var step = 0

    private struct Lesson {
        let icon: String
        let title: String
        let action: String
        let destination: NavSection
        let body: String
    }

    private let lessons: [Lesson] = [
        .init(icon: "cube.transparent", title: "1. Choose a model", action: "Open Model Builder", destination: .model,
              body: "Pick Tiny for a quick first run. The estimates update as you change layers, width, and context length."),
        .init(icon: "text.book.closed", title: "2. Pick training text", action: "Open Dataset", destination: .dataset,
              body: "Use the built-in sample, import a text file, or choose a public corpus from the marketplace. In Simple mode, the tokenizer is built when training starts."),
        .init(icon: "waveform.path.ecg", title: "3. Start training", action: "Open Training", destination: .training,
              body: "Start a run, then watch loss and the sample timeline. Lower loss usually means the model is learning the patterns in your text."),
        .init(icon: "text.cursor", title: "4. Generate and iterate", action: "Open Sampling", destination: .sampling,
              body: "Enter a prompt and generate. Blue text is the model's continuation. Change temperature or filters, then Continue to extend the same result."),
        .init(icon: "tray.full", title: "5. Fine-tune a behavior", action: "Open Fine-tune Data", destination: .fineTuneData,
              body: "Add JSONL datasets to the mixer. Select a percent or number of rows from each source, then return to Training and choose Fine-tune."),
    ]

    private var safeStep: Int {
        min(max(step, 0), max(lessons.count - 1, 0))
    }

    private var currentLesson: Lesson? {
        lessons.indices.contains(safeStep) ? lessons[safeStep] : nil
    }

    var body: some View {
        Group {
            if let lesson = currentLesson {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Image(systemName: lesson.icon).font(.system(size: 40)).foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(lesson.title).font(.title.bold())
                                Text("Hands-on guide").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(lesson.body).font(.title3).fixedSize(horizontal: false, vertical: true)
                        Button(lesson.action) {
                            NotificationCenter.default.post(name: .navigateToSection, object: lesson.destination.rawValue)
                            dismiss()
                        }
                        .buttonStyle(WorkbenchPrimaryButtonStyle())
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: completionIcon).foregroundStyle(completionIcon == "checkmark.circle.fill" ? .green : .secondary)
                            Text(completionText).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(40)
                    Divider()
                    HStack {
                        Button("Back") { step = max(0, safeStep - 1) }.disabled(safeStep == 0)
                        Spacer()
                        PageDots(count: lessons.count, index: safeStep)
                        Spacer()
                        if safeStep < lessons.count - 1 {
                            Button("Next") { step = safeStep + 1 }.keyboardShortcut(.defaultAction)
                        } else {
                            Button("Finish") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(WorkbenchPrimaryButtonStyle())
                        }
                    }.padding()
                }
            }
        }
        .frame(width: 600, height: 440)
    }

    private var completionIcon: String {
        switch safeStep {
        case 1: return state.hasCorpus ? "checkmark.circle.fill" : "circle"
        case 2: return trainer.isTraining || trainer.step > 0 ? "checkmark.circle.fill" : "circle"
        case 3: return trainer.hasModel ? "checkmark.circle.fill" : "circle"
        case 4: return state.hasFineTuneData ? "checkmark.circle.fill" : "circle"
        default: return "checkmark.circle.fill"
        }
    }

    private var completionText: String { completionIcon == "checkmark.circle.fill" ? "Completed" : "Complete this in the workspace" }
}
