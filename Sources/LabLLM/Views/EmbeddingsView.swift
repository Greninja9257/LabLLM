import SwiftUI

struct EmbeddingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var trainer: Trainer
    @State private var timer: Timer?
    @State private var iterations = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if !trainer.hasModel {
                ContentUnavailableView("No model to visualize yet", systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Train or load a model first.")).frame(maxHeight: .infinity)
            } else if state.embeddingPoints.isEmpty {
                ContentUnavailableView("No map yet", systemImage: "circle.grid.3x3",
                    description: Text("Press Compute to project the model's trained token embeddings into 2D."))
                    .frame(maxHeight: .infinity)
            } else {
                canvas.frame(maxHeight: .infinity)
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Embedding Map").font(.title2.bold())
                Text("PCA of the model's real trained token embeddings, then a similarity-based layout pass pulls related tokens together.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if state.isComputingEmbeddings {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    state.computeEmbeddingMap()
                    iterations = 0
                } label: { Label("Compute", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(WorkbenchPrimaryButtonStyle())
            }
            if !state.embeddingPoints.isEmpty {
                Button { toggleAnimation() } label: {
                    Label(timer == nil ? "Animate clustering" : "Stop", systemImage: timer == nil ? "play.fill" : "stop.fill")
                }.buttonStyle(WorkbenchSecondaryButtonStyle())
            }
        }.padding()
    }

    private var canvas: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) - 40
            let cx = geo.size.width / 2, cy = geo.size.height / 2
            ZStack {
                ForEach(state.embeddingPoints) { p in
                    Text(p.label)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(colorFor(p).opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .position(x: cx + CGFloat(p.x) * size / 2, y: cy + CGFloat(p.y) * size / 2)
                        .animation(.easeOut(duration: 0.3), value: p.x)
                }
            }
        }
        .background(Color.black.opacity(0.02))
    }

    private func colorFor(_ p: EmbeddingPoint) -> Color {
        // Hue derived from position angle so nearby clusters read as color families.
        let angle = atan2(Double(p.y), Double(p.x))
        let hue = (angle + .pi) / (2 * .pi)
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }

    private func toggleAnimation() {
        if let t = timer { t.invalidate(); timer = nil; return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            state.relaxEmbeddingMap()
            iterations += 1
            if iterations > 80 { timer?.invalidate(); timer = nil }
        }
    }
}
