import SwiftUI

@MainActor
final class DataImportState: ObservableObject {
    @Published var isRunning = false
    @Published var title = ""
    @Published var detail = ""
    @Published var completedRows = 0
    @Published var totalRows = 0
    @Published var unit = "rows"
    @Published var queuedTitles: [String] = []
    @Published var isCancelling = false

    var progress: Double { totalRows > 0 ? Double(completedRows) / Double(totalRows) : 0 }
    var percentText: String { "\(Int((progress * 100).rounded()))%" }

    func begin(title: String, detail: String, totalRows: Int, queuedTitles: [String], unit: String = "rows") {
        self.title = title
        self.detail = detail
        self.totalRows = totalRows
        self.completedRows = 0
        self.unit = unit
        self.queuedTitles = queuedTitles
        self.isCancelling = false
        self.isRunning = true
    }

    func update(completedRows: Int, detail: String) {
        self.completedRows = completedRows
        self.detail = detail
    }

    func updateQueue(_ titles: [String]) { queuedTitles = titles }

    func finish() {
        isRunning = false
        isCancelling = false
        completedRows = totalRows
        queuedTitles = []
    }
}

struct DataImportProgressPanel: View {
    @ObservedObject var state: DataImportState
    let cancel: () -> Void

    var body: some View {
        if state.isRunning {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(WorkbenchTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Button(action: cancel) {
                        Image(systemName: state.isCancelling ? "hourglass" : "xmark")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isCancelling)
                    .help("Cancel import")
                }
                ProgressView(value: state.progress)
                    .tint(WorkbenchTheme.accent)
                HStack {
                    Text("\(state.completedRows.formatted()) / \(state.totalRows.formatted()) \(state.unit)")
                    Spacer()
                    Text(state.percentText)
                    if !state.queuedTitles.isEmpty { Divider().frame(height: 10) }
                    if !state.queuedTitles.isEmpty { Text("\(state.queuedTitles.count) queued") }
                }
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                if let next = state.queuedTitles.first {
                    Text("Next: \(next)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(14)
            .frame(width: 330)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous).strokeBorder(WorkbenchTheme.grid) }
            .shadow(radius: 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
