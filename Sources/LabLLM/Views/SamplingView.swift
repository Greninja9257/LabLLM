import SwiftUI

struct SamplingView: View {
    @EnvironmentObject var trainer: Trainer
    @EnvironmentObject var tutorial: TutorialState

    @State private var prompt = "the "
    @State private var maxTokens: Double = 200
    @State private var temperature: Double = 0.8
    @State private var topK: Double = 0
    @State private var topP: Double = 1.0
    @State private var minP: Double = 0.0
    @State private var repPenalty: Double = 1.0
    @State private var greedy = false
    @State private var seedText = ""
    @State private var stopText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkbenchPageHeader(eyebrow: "Playground", title: "Sampling", subtitle: "Steer the loaded model and watch its continuation emerge token by token.", icon: "text.cursor")

                if !trainer.hasModel {
                    WorkbenchEmptyState(icon: "text.cursor", title: "No model in memory", message: "Train a model or load a checkpoint, then return here to generate.")
                } else {
                    GroupBox("Prompt") {
                        promptSurface
                    }

                    GroupBox("Decoding") {
                        VStack(spacing: 12) {
                            slider("Max tokens", $maxTokens, 16...1000, step: 8, fmt: "%.0f")
                            Toggle("Greedy (argmax)", isOn: $greedy)
                            if !greedy {
                                slider("Temperature", $temperature, 0.1...2.0, step: 0.05, fmt: "%.2f")
                                slider("Top-k (0 = off)", $topK, 0...200, step: 1, fmt: "%.0f")
                                slider("Top-p (1 = off)", $topP, 0.1...1.0, step: 0.01, fmt: "%.2f")
                                slider("Min-p (0 = off)", $minP, 0.0...0.5, step: 0.01, fmt: "%.2f")
                                slider("Repetition penalty", $repPenalty, 1.0...2.0, step: 0.05, fmt: "%.2f")
                                HStack {
                                    Text("Seed").frame(width: 160, alignment: .leading)
                                    TextField("random", text: $seedText).textFieldStyle(.roundedBorder).frame(width: 160)
                                    Spacer()
                                }
                                HStack {
                                    Text("Stop sequences").frame(width: 160, alignment: .leading)
                                    TextField("comma,separated", text: $stopText).textFieldStyle(.roundedBorder)
                                }
                            }
                        }.padding(8)
                    }

                    HStack {
                        Button {
                            trainer.sample(prompt: prompt, params: params())
                            tutorial.complete(.sampleGenerated)
                        } label: {
                            Label(trainer.isSampling ? "Generating…" : "Generate", systemImage: "sparkles")
                        }
                        .buttonStyle(WorkbenchPrimaryButtonStyle())
                        .disabled(trainer.isSampling)
                        .tutorialTarget(.sampleGenerated)
                        Button {
                            trainer.continueSample(params: params())
                        } label: {
                            Label("Continue", systemImage: "arrow.right")
                        }
                        .disabled(trainer.isSampling || trainer.sampleOutput.isEmpty)
                    }

                }
            }
            .padding(WorkbenchTheme.pagePadding)
        }
    }

    private func params() -> SamplingParams {
        let stops = stopText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return SamplingParams(
            maxTokens: Int(maxTokens),
            temperature: Float(temperature),
            topK: Int(topK),
            topP: Float(topP),
            minP: Float(minP),
            repetitionPenalty: Float(repPenalty),
            greedy: greedy,
            seed: UInt64(seedText),
            stopSequences: stops)
    }

    private var continuation: String {
        guard trainer.sampleOutput.hasPrefix(prompt) else { return trainer.sampleOutput }
        return String(trainer.sampleOutput.dropFirst(prompt.count))
    }

    @ViewBuilder private var promptSurface: some View {
        if trainer.sampleOutput.isEmpty {
            TextEditor(text: $prompt)
                .font(.callout.monospaced())
                .frame(height: 80)
                .padding(4)
        } else {
            HStack(alignment: .top, spacing: 10) {
                ScrollView {
                    (Text(prompt).foregroundStyle(.primary) + Text(continuation).foregroundStyle(.blue))
                        .font(.callout.monospaced())
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                        .textSelection(.enabled)
                }
                Button {
                    prompt = trainer.sampleOutput
                    trainer.sampleOutput = ""
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Edit prompt")
            }
            .padding(4)
            .frame(height: 88)
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double, fmt: String) -> some View {
        HStack {
            Text(label).frame(width: 160, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: fmt, value.wrappedValue)).monospacedDigit().frame(width: 60, alignment: .trailing)
        }
    }
}
