import Foundation
import Testing
@testable import LabLLM

/// Dataset cards on the Hub are YAML frontmatter plus a mix of Markdown and raw
/// HTML. These tests pin the normalization so markup never leaks into the preview.
struct DatasetCardTextTests {
    @Test func frontmatterIsRemoved() {
        let card = """
        ---
        license: apache-2.0
        task_categories:
          - text-generation
        ---

        # Tiny Corpus
        Real content.
        """
        let text = DatasetCardText.plainText(from: card)
        #expect(!text.contains("license"))
        #expect(text.hasPrefix("# Tiny Corpus"))
    }

    @Test func htmlIsFlattenedIntoReadableText() {
        let card = """
        <div align="center">
        <h1>Everyday Conversations</h1>
        <p>Short chats for <b>instruction</b> tuning.</p>
        <img src="banner.png" alt="Dataset banner">
        <a href="https://example.com">Homepage</a>
        </div>
        <ul><li>2,260 rows</li><li>English only</li></ul>
        """
        let blocks = DatasetCardText.blocks(from: card)
        #expect(blocks.contains(.heading(level: 1, text: "Everyday Conversations")))
        #expect(blocks.contains(.bullet("2,260 rows")))
        #expect(blocks.contains(.bullet("English only")))
        let joined = DatasetCardText.plainText(from: card)
        #expect(!joined.contains("<"))
        #expect(joined.contains("Dataset banner"))
        #expect(joined.contains("Homepage"))
    }

    @Test func scriptAndCommentContentIsDropped() {
        let card = """
        <!-- internal note: do not show -->
        <script>window.tracking = true;</script>
        <style>.a { color: red; }</style>
        Visible text.
        """
        let text = DatasetCardText.plainText(from: card)
        #expect(text == "Visible text.")
    }

    @Test func entitiesAreDecoded() {
        let card = "Q&amp;A &mdash; &quot;chat&quot; &#39;style&#39; &#8212; done &lt;tag&gt;"
        let text = DatasetCardText.plainText(from: card)
        #expect(text == "Q&A — \"chat\" 'style' — done <tag>")
    }

    @Test func markdownStructureStillClassifies() {
        let card = """
        ## Usage

        > Load it with the viewer.

        ```python
        load_dataset("x")
        ```

        | col | type |
        """
        let blocks = DatasetCardText.blocks(from: card)
        #expect(blocks.contains(.heading(level: 2, text: "Usage")))
        #expect(blocks.contains(.quote("Load it with the viewer.")))
        #expect(blocks.contains(.code("load_dataset(\"x\")")))
        #expect(blocks.contains(.table("| col | type |")))
    }
}
