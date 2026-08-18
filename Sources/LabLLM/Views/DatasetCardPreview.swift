import SwiftUI

/// Renders a Hugging Face dataset card. The source is a mix of Markdown, YAML
/// frontmatter and raw HTML, so `DatasetCardText` flattens it first and this view
/// only has to style the resulting blocks.
struct DatasetCardPreview: View {
    let markdown: String
    var maxHeight: CGFloat = 360

    private var blocks: [DatasetCardText.Block] { DatasetCardText.blocks(from: markdown) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if blocks.isEmpty {
                    Text("This dataset has no README to display.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(blocks) { block in view(for: block) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxHeight: maxHeight)
    }

    @ViewBuilder private func view(for block: DatasetCardText.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, level <= 2 ? 6 : 2)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•").font(.callout).foregroundStyle(WorkbenchTheme.accent)
                inline(text).font(.callout).foregroundStyle(.secondary)
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(WorkbenchTheme.accent.opacity(0.5)).frame(width: 2)
                inline(text).font(.callout.italic()).foregroundStyle(.secondary)
            }
        case .code(let text):
            Text(text)
                .font(.caption.monospaced())
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WorkbenchTheme.elevatedPanel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        case .table(let row):
            Text(row).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
        case .rule:
            Divider()
        case .paragraph(let text):
            inline(text).font(.callout).foregroundStyle(.secondary)
        }
    }

    /// Bold, italics and links still arrive as Markdown inside a line, so let
    /// AttributedString handle the inline layer and fall back to plain text.
    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(text)
    }
}
