import SwiftUI
import AppKit

/// The on-disk dataset library. Anything installed here survives a relaunch, and is
/// what the Training page's mix panel picks from. Mixing itself is deliberately not
/// here — this page installs and manages data, Training decides how a run uses it.
struct InstalledDatasetsPanel: View {
    let kind: InstalledDataset.Kind

    @EnvironmentObject var state: AppState
    @EnvironmentObject var library: DatasetLibrary
    @EnvironmentObject var models: ModelStore

    @State private var renaming: InstalledDataset?
    @State private var renameValue = ""
    @State private var deleting: InstalledDataset?

    private var installed: [InstalledDataset] { library.datasets(of: kind) }

    var body: some View {
        GroupBox(kind == .corpus ? "Installed pre-training data" : "Installed fine-tuning data") {
            VStack(alignment: .leading, spacing: 10) {
                header
                if installed.isEmpty {
                    Text("Nothing installed yet. Importing a dataset writes it to disk, so it is still here next time you open LabLLM.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(installed) { dataset in row(dataset) }
                }
            }.padding(8)
        }
        .alert("Rename dataset", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Dataset name", text: $renameValue)
            Button("Rename") {
                if let dataset = renaming { library.rename(dataset, to: renameValue) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Delete \(deleting?.name ?? "dataset")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let dataset = deleting { state.uninstall(dataset) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("This removes the file from disk and from every model's training mix.")
        }
    }

    private var header: some View {
        HStack {
            Text("\(installed.count) installed · \(ByteCountFormatter.string(fromByteCount: Int64(installed.reduce(0) { $0 + $1.bytes }), countStyle: .file)) on disk")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Button("Open library folder") {
                NSWorkspace.shared.activateFileViewerSelecting([DatasetLibrary.rootDirectory()])
            }.buttonStyle(WorkbenchSecondaryButtonStyle())
            Button("Set up the mix in Training") {
                NotificationCenter.default.post(name: .navigateToSection, object: NavSection.training.rawValue)
            }.buttonStyle(WorkbenchSecondaryButtonStyle())
        }
    }

    private func row(_ dataset: InstalledDataset) -> some View {
        let inMix = isInMix(dataset)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: dataset.kind.icon).foregroundStyle(.tint)
                Text(dataset.name).font(.callout.weight(.semibold)).lineLimit(1)
                if inMix {
                    Text("IN MIX").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.18), in: Capsule()).foregroundStyle(.green)
                }
                Spacer()
                Text(dataset.installedAt, style: .date).font(.caption2).foregroundStyle(.secondary)
            }
            Text(dataset.origin).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Text(dataset.summary).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if inMix {
                    Button("Remove from \(models.activeName)") { state.removeFromMix(dataset.id, kind: dataset.kind) }
                        .buttonStyle(WorkbenchSecondaryButtonStyle())
                } else {
                    Button("Add to \(models.activeName)") { state.addToMix(dataset) }
                        .buttonStyle(WorkbenchPrimaryButtonStyle())
                }
                Menu {
                    Button("Rename…") { renaming = dataset; renameValue = dataset.name }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([library.fileURL(for: dataset)])
                    }
                    Divider()
                    Button("Delete from disk…", role: .destructive) { deleting = dataset }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).frame(width: 34)
            }
        }
        .padding(10)
        .background(WorkbenchTheme.elevatedPanel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
    }

    private func isInMix(_ dataset: InstalledDataset) -> Bool {
        let mix = dataset.kind == .corpus ? state.corpusMix : state.fineTuneMix
        return mix.contains { $0.datasetID == dataset.id }
    }
}
