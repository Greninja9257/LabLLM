import SwiftUI

/// Filter controls for the dataset browser panes. Kept compact because it lives in
/// a ~300pt sidebar next to the search field.
struct DatasetFilterBar: View {
    @ObservedObject var browser: HFHubBrowser

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(browser.filters.activeCount > 0 ? WorkbenchTheme.accent : .secondary)
                TextField("Filter loaded results", text: $browser.filters.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                if browser.filters.activeCount > 0 {
                    Button {
                        browser.resetFilters()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear \(browser.filters.activeCount) active filter\(browser.filters.activeCount == 1 ? "" : "s")")
                }
            }

            HStack(spacing: 6) {
                menu(label: browser.filters.category.label, isActive: browser.filters.category != .any) {
                    ForEach(DatasetCategory.choices(for: browser.kind)) { category in
                        Button(category.label) { browser.filters.category = category }
                    }
                }
                menu(label: browser.filters.sort.label, isActive: browser.filters.sort != .relevance) {
                    ForEach(DatasetSort.allCases) { sort in
                        Button(sort.label) { browser.filters.sort = sort }
                    }
                }
            }

            HStack(spacing: 6) {
                menu(label: browser.filters.size.label, isActive: browser.filters.size != .any) {
                    ForEach(DatasetSize.allCases) { size in
                        Button(size.label) { browser.filters.size = size }
                    }
                }
                menu(label: browser.filters.popularity.label, isActive: browser.filters.popularity != .any) {
                    ForEach(DatasetPopularity.allCases) { popularity in
                        Button(popularity.label) { browser.filters.popularity = popularity }
                    }
                }
                menu(label: browser.filters.language.label, isActive: browser.filters.language != .any) {
                    ForEach(DatasetLanguage.allCases) { language in
                        Button(language.label) { browser.filters.language = language }
                    }
                }
            }
        }
    }

    private func menu<Content: View>(label: String, isActive: Bool, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            Text(label)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(isActive ? WorkbenchTheme.accent : .secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(isActive ? WorkbenchTheme.accent.opacity(0.12) : WorkbenchTheme.elevatedPanel,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
