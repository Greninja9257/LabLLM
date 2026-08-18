import SwiftUI

struct XRayView: View {
    @EnvironmentObject var trainer: Trainer
    @State private var prompt = "the "
    @State private var maxTokens: Double = 40
    @State private var temperature: Double = 0.8
    @State private var topK: Double = 40
    @State private var selected: XRayStep.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if !trainer.hasModel {
                // The enclosing stack is leading-aligned, so the placeholder needs the
                // full width to sit in the middle of the page rather than hugging the edge.
                ContentUnavailableView("No model to inspect yet", systemImage: "eye",
                    description: Text("Train or load a model first."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    tokenStream.frame(minWidth: 380)
                    detailPanel.frame(minWidth: 320)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("X-Ray").font(.title2.bold())
                    Text("Click any generated token to see the model's real probability, entropy, and alternatives.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    trainer.xrayGenerate(prompt: prompt, params: SamplingParams(
                        maxTokens: Int(maxTokens), temperature: Float(temperature), topK: Int(topK)))
                } label: {
                    Label(trainer.isXraying ? "Generating…" : "Generate", systemImage: "sparkles")
                }.buttonStyle(WorkbenchPrimaryButtonStyle()).disabled(trainer.isXraying)
            }
            HStack(spacing: 16) {
                TextField("Prompt", text: $prompt).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                slider("Tokens", $maxTokens, 5...150, "%.0f")
                slider("Temp", $temperature, 0.1...2.0, "%.2f")
                slider("Top-k", $topK, 0...200, "%.0f")
            }
        }.padding()
    }

    private func slider(_ label: String, _ v: Binding<Double>, _ range: ClosedRange<Double>, _ fmt: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Slider(value: v, in: range).frame(width: 90)
            Text(String(format: fmt, v.wrappedValue)).font(.caption.monospaced()).frame(width: 40)
        }
    }

    private var tokenStream: some View {
        ScrollView {
            FlowTokens(steps: trainer.xraySteps, selected: $selected)
                .padding()
        }
    }

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let step = trainer.xraySteps.first(where: { $0.id == selected }) ?? trainer.xraySteps.last {
                    Text("Selected token").font(.caption).foregroundStyle(.secondary)
                    Text("\"\(step.chosenText)\"").font(.title2.monospaced().bold())

                    HStack(spacing: 24) {
                        stat("Probability", String(format: "%.1f%%", step.chosenProb * 100))
                        stat("Entropy", String(format: "%.2f nats", step.entropy))
                    }

                    Text("TOP CANDIDATES").font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 8)
                    VStack(spacing: 6) {
                        ForEach(step.candidates) { c in
                            HStack {
                                Text("\"\(c.tokenText)\"").font(.callout.monospaced())
                                    .foregroundStyle(c.tokenText == step.chosenText ? Color.accentColor : .primary)
                                Spacer()
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.15))
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(c.tokenText == step.chosenText ? Color.accentColor : Color.secondary)
                                            .frame(width: geo.size.width * CGFloat(c.prob))
                                    }
                                }.frame(height: 14)
                                Text(String(format: "%.1f%%", c.prob * 100)).font(.caption.monospacedDigit()).frame(width: 46)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No token selected", systemImage: "hand.tap", description: Text("Generate, then click a token on the left."))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }.padding()
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A simple wrapping token stream where each piece is tappable and shaded by
/// how confident the model was (darker = more probable).
private struct FlowTokens: View {
    let steps: [XRayStep]
    @Binding var selected: XRayStep.ID?

    var body: some View {
        var rows: [[XRayStep]] = [[]]
        var rowWidth: CGFloat = 0
        let maxWidth: CGFloat = 340
        for step in steps {
            let w = CGFloat(step.chosenText.count) * 9 + 16
            if rowWidth + w > maxWidth { rows.append([]); rowWidth = 0 }
            rows[rows.count - 1].append(step)
            rowWidth += w
        }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(rows[r]) { step in
                        Text(step.chosenText.isEmpty ? "·" : step.chosenText)
                            .font(.callout.monospaced())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(
                                (selected == step.id ? Color.accentColor : Color.accentColor.opacity(Double(step.chosenProb) * 0.8 + 0.1)),
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .foregroundStyle(selected == step.id ? .white : .primary)
                            .onTapGesture { selected = step.id }
                    }
                }
            }
        }
    }
}
