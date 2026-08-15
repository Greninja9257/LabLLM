import SwiftUI

/// Drives the loading overlay. Anything slow (building a tokenizer over a large
/// corpus, preparing a training run, loading a checkpoint) publishes progress here.
final class LoadingState: ObservableObject, @unchecked Sendable {
    @Published var isLoading = false
    @Published var title = ""
    @Published var detail = ""
    @Published var progress: Double? = nil   // nil = indeterminate

    func begin(_ title: String, detail: String = "") {
        DispatchQueue.main.async {
            self.title = title; self.detail = detail; self.progress = nil; self.isLoading = true
        }
    }
    func update(detail: String, progress: Double? = nil) {
        DispatchQueue.main.async { self.detail = detail; self.progress = progress }
    }
    func end() {
        DispatchQueue.main.async { self.isLoading = false }
    }
}

struct LoadingOverlay: View {
    @ObservedObject var state: LoadingState

    var body: some View {
        if state.isLoading {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 14) {
                    if let p = state.progress {
                        ProgressView(value: p).frame(width: 220)
                        Text("\(Int((p * 100).rounded()))%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.large)
                    }
                    Text(state.title).font(.headline)
                    if !state.detail.isEmpty {
                        Text(state.detail).font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(28)
                .frame(minWidth: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 20)
            }
            .transition(.opacity)
        }
    }
}
