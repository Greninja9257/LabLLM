import SwiftUI

struct EstimatorView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let cfg = state.gptConfig
        let tc = state.trainConfig
        let params = cfg.estimatedParameters

        // Rough memory: weights + AdamW state (2x) + gradients (1x), fp32 (~16 B/param),
        // plus a crude activation term.
        let optimizerBytes = params * 16
        let activationBytes = tc.batchSize * cfg.blockSize * cfg.nEmbd * cfg.nLayers * 4 * 4
        let totalMemMB = Double(optimizerBytes + activationBytes) / 1_048_576.0

        let tokensPerStep = tc.batchSize * cfg.blockSize
        let totalTokens = tokensPerStep * tc.maxSteps

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkbenchPageHeader(eyebrow: "Analyze", title: "Resource Estimator", subtitle: "A practical read on memory, weights, and token volume before committing to a run.", icon: "function")

                GroupBox("Model") {
                    grid {
                        cell("Parameters", format(params))
                        cell("Weights (fp32)", "\(format(params * 4 / 1_048_576)) MB")
                        cell("Weights (fp16)", "\(format(params * 2 / 1_048_576)) MB")
                        cell("Head dim", "\(cfg.nHeads == 0 ? 0 : cfg.nEmbd / cfg.nHeads)")
                    }
                }

                GroupBox("Training memory (rough)") {
                    grid {
                        cell("Optimizer state", "\(format(optimizerBytes / 1_048_576)) MB")
                        cell("Activations", "\(format(activationBytes / 1_048_576)) MB")
                        cell("Peak (est.)", "\(format(Int(totalMemMB))) MB")
                        cell("Unified RAM", String(format: "%.0f GB", state.hardware.physicalMemoryGB))
                    }
                }

                GroupBox("Data") {
                    grid {
                        cell("Tokens / step", format(tokensPerStep))
                        cell("Total tokens", format(totalTokens))
                        cell("Steps", format(tc.maxSteps))
                        // Only measurable once the selected mix has been read off disk;
                        // otherwise fall back to the character estimate from metadata.
                        cell("Corpus tokens", corpusTokenEstimate)
                    }
                }

                let fits = totalMemMB < (state.hardware.physicalMemoryGB - 3) * 1024
                Label(fits ? "Should fit comfortably in unified memory." :
                             "Peak memory may approach your RAM — reduce batch size, context, or model size.",
                      systemImage: fits ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(fits ? .green : .orange)

                Text("These are order-of-magnitude estimates, not measurements. Real usage depends on MLX's lazy allocation, precision, and graph fusion.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(WorkbenchTheme.pagePadding)
        }
    }

    private var corpusTokenEstimate: String {
        if state.isCorpusLoaded, let tokenizer = state.tokenizer {
            return format(tokenizer.encode(state.corpus).count)
        }
        guard state.hasCorpus else { return "—" }
        return "≈ \(format(state.corpusCharCount))"
    }

    private func grid<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), spacing: 14, content: c)
            .padding(8)
    }
    private func cell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func format(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
