import SwiftUI
import AppKit

struct CheckpointsView: View {
    @EnvironmentObject var state: AppState
    @State private var items: [CheckpointItem] = []
    @State private var bestURL: URL?
    @State private var quantizeError: String?
    @State private var quantizeResult: String?
    @State private var renaming: CheckpointItem?
    @State private var renameValue = ""

    struct CheckpointItem: Identifiable {
        let id = UUID()
        let url: URL
        let meta: Checkpoint.Meta
        var name: String { url.lastPathComponent }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    WorkbenchPageHeader(eyebrow: "Run Studio", title: "Model Manager", subtitle: "Inspect, continue, duplicate, quantize, and organize locally saved models.", icon: "cube.box")
                    Spacer()
                    Button { refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }

                if let r = quantizeResult {
                    Label(r, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if let e = quantizeError {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }

                if items.isEmpty {
                    ContentUnavailableView("No checkpoints yet", systemImage: "tray",
                        description: Text("Finish (or stop) a training run and it will be saved here automatically."))
                        .frame(height: 220)
                } else {
                    ForEach(items) { item in row(item) }
                }
            }.padding(WorkbenchTheme.pagePadding)
        }
        .onAppear(perform: refresh)
        .alert("Rename model", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Model name", text: $renameValue)
            Button("Rename") { renameSelected() }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: { Text("Use a concise local name for this checkpoint.") }
    }

    private func row(_ item: CheckpointItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cube.box").foregroundStyle(.tint)
                Text(item.name).font(.headline)
                if item.url == bestURL {
                    Text("BEST").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.2), in: Capsule()).foregroundStyle(.green)
                }
                if item.meta.loraRank != nil {
                    Text("LoRA").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15), in: Capsule()).foregroundStyle(.purple)
                }
                Spacer()
                Text(item.meta.method).font(.caption).foregroundStyle(.secondary)
                Text(item.meta.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                stat("Step", "\(item.meta.step)")
                stat("Loss", String(format: "%.3f", item.meta.loss))
                stat("Val", item.meta.valLoss > 0 ? String(format: "%.3f", item.meta.valLoss) : "—")
                stat("Params", format(item.meta.config.estimatedParameters))
                stat("Vocab", "\(item.meta.config.vocabSize)")
            }
            HStack {
                Button("Load for sampling") { state.loadCheckpoint(item.url, meta: item.meta) }.buttonStyle(WorkbenchSecondaryButtonStyle())
                Button("Continue training") { state.prepareContinuation(from: item.url, meta: item.meta, asFineTune: false) }
                    .buttonStyle(WorkbenchSecondaryButtonStyle())
                    .disabled(item.meta.quantizedBits != nil)
                Button("Continue fine-tuning") { state.prepareContinuation(from: item.url, meta: item.meta, asFineTune: true) }
                    .buttonStyle(WorkbenchPrimaryButtonStyle())
                    .disabled(item.meta.quantizedBits != nil)
                Menu("Quantize") {
                    Button("8-bit") { quantize(item, bits: 8) }
                    Button("4-bit") { quantize(item, bits: 4) }
                }.menuStyle(.borderlessButton).frame(width: 100)
                Button("View model card") { NSWorkspace.shared.open(item.url.appendingPathComponent("model_card.md")) }
                    .buttonStyle(WorkbenchSecondaryButtonStyle())
                Menu {
                    Button("Rename") { renaming = item; renameValue = item.name }
                    Button("Duplicate") { duplicate(item) }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                Button(role: .destructive) {
                    try? FileManager.default.removeItem(at: item.url); refresh()
                } label: { Text("Delete") }.buttonStyle(WorkbenchSecondaryButtonStyle())
            }
        }
        .padding(14)
        .background(WorkbenchTheme.panel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous).strokeBorder(WorkbenchTheme.grid) }
    }

    private func quantize(_ item: CheckpointItem, bits: Int) {
        quantizeError = nil; quantizeResult = nil
        state.quantizeCheckpoint(item.url, bits: bits) { result in
            switch result {
            case .success(let (url, origBytes, qBytes)):
                let origMB = Double(origBytes) / 1_048_576, qMB = Double(qBytes) / 1_048_576
                quantizeResult = "Saved \(url.lastPathComponent) — \(String(format: "%.1f", origMB)) MB → \(String(format: "%.1f", qMB)) MB"
                refresh()
            case .failure(let error):
                quantizeError = "Quantization failed: \(error.localizedDescription)"
            }
        }
    }

    private func refresh() {
        items = Checkpoint.list().compactMap { url in
            guard let meta = try? Checkpoint.loadMeta(from: url) else { return nil }
            return CheckpointItem(url: url, meta: meta)
        }
        bestURL = Checkpoint.best()
    }

    private func renameSelected() {
        guard let item = renaming else { return }
        let name = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty else { return }
        do {
            try FileManager.default.moveItem(at: item.url, to: item.url.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true))
            quantizeResult = "Renamed model to \(name)"
        } catch { quantizeError = "Couldn't rename model: \(error.localizedDescription)" }
        renaming = nil
        refresh()
    }

    private func duplicate(_ item: CheckpointItem) {
        let copyName = "\(item.name)-copy-\(Int(Date().timeIntervalSince1970))"
        do {
            try FileManager.default.copyItem(at: item.url, to: item.url.deletingLastPathComponent().appendingPathComponent(copyName, isDirectory: true))
            quantizeResult = "Duplicated \(item.name)"
        } catch { quantizeError = "Couldn't duplicate model: \(error.localizedDescription)" }
        refresh()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.callout.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func format(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
