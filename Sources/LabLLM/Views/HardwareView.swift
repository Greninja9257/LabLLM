import SwiftUI

struct HardwareView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let hw = state.hardware
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkbenchPageHeader(eyebrow: "Analyze", title: "Hardware", subtitle: "The Apple Silicon resources available to this local model studio.", icon: "cpu")

                if !hw.isAppleSilicon {
                    Label("Not running on Apple Silicon — MLX training requires an M-series chip.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                GroupBox("Chip") {
                    VStack(alignment: .leading, spacing: 10) {
                        row("Processor", hw.chip)
                        row("Apple Silicon", hw.isAppleSilicon ? "Yes" : "No")
                        row("Logical cores", "\(hw.processorCount)")
                        if hw.performanceCores > 0 {
                            row("Performance cores", "\(hw.performanceCores)")
                            row("Efficiency cores", "\(hw.efficiencyCores)")
                        }
                        row("Unified memory", String(format: "%.0f GB", hw.physicalMemoryGB))
                    }.padding(8)
                }

                GroupBox("Guidance") {
                    VStack(alignment: .leading, spacing: 10) {
                        row("Recommended max params", format(hw.recommendedMaxParameters))
                        let fits = state.gptConfig.estimatedParameters <= hw.recommendedMaxParameters
                        HStack {
                            Text("Current model fits").frame(width: 200, alignment: .leading)
                            Label(fits ? "Comfortably" : "May be tight",
                                  systemImage: fits ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(fits ? .green : .orange)
                        }
                        Text("Guidance is a rough upper bound assuming fp32 AdamW state. Real usage depends on batch size, context length, and precision.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
            }
            .padding(WorkbenchTheme.pagePadding)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).frame(width: 200, alignment: .leading).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
            Spacer()
        }
    }

    private func format(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
