import SwiftUI
import AppKit

/// The top-left box in the sidebar. Clicking it opens a styled model panel: the
/// models in the studio plus create/rename/duplicate/delete actions, the way a
/// project switcher works in a document app. It is a custom popover rather than a
/// `Menu` so the list can show per-model detail and match the workbench styling.
struct ModelSwitcherView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var models: ModelStore
    @EnvironmentObject var trainer: Trainer

    @State private var isOpen = false
    @State private var isCreating = false
    @State private var isRenaming = false
    @State private var isConfirmingDelete = false
    @State private var draftName = ""
    @State private var hoveredRow: UUID?
    @State private var hoveredAction: String?
    /// Counting checkpoints touches the filesystem, so it is refreshed on the
    /// events that can change it rather than on every redraw of the sidebar.
    @State private var checkpointCount = 0

    var body: some View {
        Button { isOpen.toggle() } label: { box }
            .buttonStyle(.plain)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) { panel }
            .onAppear(perform: refreshCheckpointCount)
            .onChange(of: models.activeID) { _ in refreshCheckpointCount() }
            .onChange(of: trainer.lastCheckpointDir) { _ in refreshCheckpointCount() }
            .alert("New model", isPresented: $isCreating) {
                TextField("Model name", text: $draftName)
                Button("Create") { state.createModel(named: draftName); refreshCheckpointCount() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("A model keeps its own architecture, hyperparameters, training data mix, and checkpoints.")
            }
            .alert("Rename model", isPresented: $isRenaming) {
                TextField("Model name", text: $draftName)
                Button("Rename") { state.renameActiveModel(to: draftName) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Renaming affects this model only. Its checkpoints stay where they are.")
            }
            .alert("Delete \(models.activeName)?", isPresented: $isConfirmingDelete) {
                Button("Delete", role: .destructive) { state.deleteActiveModel(); refreshCheckpointCount() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes the model and its checkpoints. Installed datasets are kept.")
            }
            .alert("Model problem", isPresented: Binding(get: { models.lastError != nil }, set: { if !$0 { models.lastError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(models.lastError ?? "") }
    }

    // MARK: - Collapsed box

    private var box: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WorkbenchTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("LABLLM").font(.caption2.weight(.bold)).foregroundStyle(WorkbenchTheme.accent)
                Text(models.activeName).font(.callout.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(isOpen ? Color.white : WorkbenchTheme.accent)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .frame(width: 20, height: 20)
                .background(isOpen ? WorkbenchTheme.accent : WorkbenchTheme.accent.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .animation(.easeInOut(duration: 0.15), value: isOpen)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchTheme.elevatedPanel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                .strokeBorder(isOpen ? WorkbenchTheme.accent.opacity(0.55) : WorkbenchTheme.grid)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        guard models.activeID != nil else { return "No model selected" }
        return "\(checkpointCount) checkpoint\(checkpointCount == 1 ? "" : "s") · \(state.corpusName)"
    }

    // MARK: - Drop-down panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MODELS")
                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(models.models) { workspace in modelRow(workspace) }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 260)

            Divider().padding(.vertical, 6)

            VStack(spacing: 2) {
                action("New model…", icon: "plus.circle") {
                    draftName = ""
                    isOpen = false
                    isCreating = true
                }
                action("Rename model…", icon: "pencil") {
                    draftName = models.activeName
                    isOpen = false
                    isRenaming = true
                }
                action("Duplicate model", icon: "square.on.square") {
                    isOpen = false
                    state.duplicateActiveModel()
                    refreshCheckpointCount()
                }
                action("Reveal in Finder", icon: "folder") {
                    isOpen = false
                    guard let id = models.activeID else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([models.directory(for: id)])
                }
                action("Delete model…", icon: "trash", tone: .red, enabled: models.models.count > 1) {
                    isOpen = false
                    isConfirmingDelete = true
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 10)
        }
        .frame(width: 302)
        .background(WorkbenchTheme.elevatedPanel)
    }

    private func modelRow(_ workspace: ModelWorkspace) -> some View {
        let isActive = workspace.id == models.activeID
        let isHovered = hoveredRow == workspace.id
        return Button {
            isOpen = false
            state.activateModel(workspace.id)
            refreshCheckpointCount()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: isActive ? "cube.fill" : "cube")
                    .foregroundStyle(isActive ? Color.white : WorkbenchTheme.accent)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(workspace.name)
                        .font(.callout.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Color.white : Color.primary)
                        .lineLimit(1)
                    Text(rowDetail(workspace))
                        .font(.caption2)
                        .foregroundStyle(isActive ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isActive {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(isActive: isActive, isHovered: isHovered),
                        in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredRow = $0 ? workspace.id : (hoveredRow == workspace.id ? nil : hoveredRow) }
    }

    private func rowBackground(isActive: Bool, isHovered: Bool) -> Color {
        if isActive { return WorkbenchTheme.accent }
        return isHovered ? WorkbenchTheme.accent.opacity(0.12) : .clear
    }

    private func rowDetail(_ workspace: ModelWorkspace) -> String {
        let count = models.checkpointCount(for: workspace.id)
        let layers = "\(workspace.gptConfig.nLayers)L · \(workspace.gptConfig.nEmbd)d"
        return "\(count) checkpoint\(count == 1 ? "" : "s") · \(layers)"
    }

    private func action(_ title: String, icon: String, tone: Color = .primary, enabled: Bool = true,
                        perform: @escaping () -> Void) -> some View {
        let isHovered = hoveredAction == title && enabled
        return Button(action: perform) {
            HStack(spacing: 9) {
                Image(systemName: icon).frame(width: 16).foregroundStyle(enabled ? tone : Color.secondary)
                Text(title).foregroundStyle(enabled ? tone : Color.secondary)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? tone.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hoveredAction = $0 ? title : (hoveredAction == title ? nil : hoveredAction) }
    }

    private func refreshCheckpointCount() {
        checkpointCount = models.activeID.map(models.checkpointCount(for:)) ?? 0
    }
}
