import SwiftUI

/// The scrolling result list for both dataset browsers. Paging is driven by row
/// index rather than by "is this the last element", so it keeps working when
/// filters and sorting reorder or shorten the list.
struct DatasetResultList: View {
    @ObservedObject var browser: HFHubBrowser

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                let rows = browser.visibleResults
                ForEach(Array(rows.enumerated()), id: \.element.rowKey) { index, dataset in
                    DatasetResultRow(dataset: dataset,
                                     kind: browser.kind,
                                     isSelected: browser.selected == dataset,
                                     recommended: browser.isPinned(dataset))
                        .contentShape(Rectangle())
                        .onTapGesture { browser.select(dataset) }
                        .onAppear { browser.loadMoreIfNeeded(at: index) }
                }
                footer(visibleCount: rows.count)
            }
        }
    }

    @ViewBuilder private func footer(visibleCount: Int) -> some View {
        if browser.isLoadingMore {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading more…").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
        } else if visibleCount == 0 {
            VStack(spacing: 8) {
                Text(browser.filters.activeCount > 0 ? "No loaded dataset matches these filters." : "No importable datasets matched this search.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if browser.filters.activeCount > 0 {
                    Button("Clear filters") { browser.resetFilters() }
                        .buttonStyle(WorkbenchSecondaryButtonStyle())
                }
                if browser.canLoadMore {
                    Button("Keep searching") { browser.search(reset: false) }
                        .buttonStyle(WorkbenchSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 8)
        } else if !browser.canLoadMore {
            Text("End of results")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
    }
}

private struct DatasetResultRow: View {
    let dataset: HFHubDataset
    let kind: HFHubBrowser.Kind
    let isSelected: Bool
    let recommended: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(dataset.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if recommended { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
            }
            Text(dataset.id).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 8) {
                Text(dataset.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Text(trailingMetric).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isSelected ? WorkbenchTheme.accent.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
    }

    /// Whichever number tells you the most about this row: size for corpora, rows
    /// for fine-tuning data, downloads when neither is published.
    private var trailingMetric: String {
        if kind == .corpus, let size = dataset.downloadSize { return size }
        if let rows = dataset.approximateRows { return "\(rows.formatted(.number.notation(.compactName))) rows" }
        if let downloads = dataset.downloads { return "\(downloads.formatted(.number.notation(.compactName))) ↓" }
        return "—"
    }
}

extension HFHubDataset {
    /// Stable identity for list rows. Two pinned entries can share a repository id
    /// (different files of the same dataset), so the title participates.
    var rowKey: String { "\(id)|\(displayName)" }
}
