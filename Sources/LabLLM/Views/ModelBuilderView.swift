import SwiftUI

struct ModelBuilderView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var tutorial: TutorialState

    private let presets: [(String, GPTConfig)] = [
        ("Tiny",   GPTConfig(blockSize: 64,  nEmbd: 128, nLayers: 4,  nHeads: 4)),
        ("Small",  GPTConfig(blockSize: 128, nEmbd: 256, nLayers: 6,  nHeads: 8)),
        ("Medium", GPTConfig(blockSize: 256, nEmbd: 512, nLayers: 8,  nHeads: 8)),
        ("Large",  GPTConfig(blockSize: 512, nEmbd: 768, nLayers: 12, nHeads: 12)),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkbenchPageHeader(eyebrow: "Architecture", title: "Model Builder", subtitle: "Shape the decoder that will learn from your corpus. Estimates update as you work.", icon: "cube.transparent")

                GroupBox("Start from a profile") {
                    HStack(spacing: 10) {
                        ForEach(presets, id: \.0) { name, cfg in
                            Button(name) {
                                var c = cfg
                                c.vocabSize = state.gptConfig.vocabSize
                                state.gptConfig = c
                                tutorial.complete(.modelPreset)
                            }.buttonStyle(WorkbenchSecondaryButtonStyle()).controlSize(.large)
                        }
                    }.padding(6)
                }
                .tutorialTarget(.modelPreset)

                GroupBox("Architecture") {
                    VStack(spacing: 14) {
                        stepper("Context length", $state.gptConfig.blockSize, 16...2048, step: 16)
                        stepper("Hidden dimension", $state.gptConfig.nEmbd, 32...2048, step: 32)
                        stepper("Layers", $state.gptConfig.nLayers, 1...48, step: 1)
                        stepper("Attention heads", $state.gptConfig.nHeads, 1...32, step: 1)
                        stepper("MLP ratio", $state.gptConfig.mlpRatio, 1...8, step: 1)
                        Toggle("Tie embedding & output weights", isOn: $state.gptConfig.tieWeights)
                    }.padding(8)
                }

                estimatesPanel
                validationPanel
            }
            .padding(WorkbenchTheme.pagePadding)
        }
    }

    private var estimatesPanel: some View {
        GroupBox("Live estimate") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                WorkbenchMetric(label: "Parameters", value: format(state.gptConfig.estimatedParameters), icon: "cpu")
                WorkbenchMetric(label: "Vocabulary", value: "\(state.gptConfig.vocabSize)", icon: "textformat")
                WorkbenchMetric(label: "Head dimension", value: "\(state.gptConfig.nHeads == 0 ? 0 : state.gptConfig.nEmbd / state.gptConfig.nHeads)", icon: "circle.grid.cross")
                let bytes = state.gptConfig.estimatedParameters * 4
                WorkbenchMetric(label: "FP32 weights", value: "\(format(bytes / 1_048_576)) MB", icon: "internaldrive")
            }
        }
    }

    @ViewBuilder private var validationPanel: some View {
        let errors = state.gptConfig.validationErrors
        if errors.isEmpty {
            Label("Configuration valid", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(errors, id: \.self) { e in
                    Label(e, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout)
                }
            }
        }
    }

    private func stepper(_ label: String, _ value: Binding<Int>, _ range: ClosedRange<Int>, step: Int) -> some View {
        HStack {
            Text(label).frame(width: 160, alignment: .leading)
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Int($0) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
            Text("\(value.wrappedValue)").monospacedDigit().frame(width: 60, alignment: .trailing)
        }
    }

    private func format(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
