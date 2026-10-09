import Foundation
import Testing
@testable import RSSReader

@Suite("Article Screen / Accordion Rendering")
@MainActor
struct ArticleScreenAccordionRenderingTests {
    private func render(_ html: String) -> [ArticleScreenBodyBlock] {
        ArticleScreenContentState(article: makeReaderArticleDTO(contentHTML: html)).body.blocks
    }

    private func item(_ title: String = "Title", id: String = "one", state: String? = "false", panel: String = "<p>Panel</p>") -> String {
        let expanded = state.map { "aria-expanded=\"\($0)\"" } ?? ""
        return """
        <div class="wp-block-accordion-item">
          <h3><button \(expanded) aria-controls="\(id)-panel" id="\(id)" class="wp-block-accordion-heading__toggle">
            <span class="wp-block-accordion-heading__toggle-title">\(title)</span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span>
          </button></h3>
          <div id="\(id)-panel" class="wp-block-accordion-panel">\(panel)</div>
        </div>
        """
    }

    @Test
    func staticWordPressSaveAndInitialStates() throws {
        let staticHTML = """
        <div class="wp-block-accordion-item">
        <h3><button class="wp-block-accordion-heading__toggle"><span>Static title</span></button></h3>
        <div class="wp-block-accordion-panel"><p>Static panel</p></div>
        </div>
        """
        let blocks = render(staticHTML + item(id: "two", state: "true") + item(id: "three", state: nil))
        #expect(blocks.count == 3)
        let disclosures = blocks.compactMap { if case .disclosure(let value) = $0 { value } else { nil } }
        #expect(disclosures.count == 3)
        #expect(disclosures.map(\.isInitiallyExpanded) == [false, true, false])
        #expect(disclosures.first?.summary.plainText == "Static title")
    }

    @Test
    func nestedPanelsKeepSourceOrderAndOwnership() throws {
        let nested = item("Nested", id: "nested", state: "true")
        let html = item("Outer", panel: """
        <p>Before <a href="https://example.com/link">link</a></p>
        <ul><li>List entry</li></ul>
        <img src="https://example.com/image.png">
        <aside><p>Aside</p></aside>
        \(nested)
        <p>After</p>
        """)
        let blocks = render(html)
        guard case .disclosure(let outer) = try #require(blocks.first) else { Issue.record("Missing outer disclosure"); return }
        #expect(outer.content.count == 6)
        guard case .paragraph(let paragraph) = outer.content[0],
              case .list = outer.content[1],
              case .image = outer.content[2],
              case .aside = outer.content[3],
              case .disclosure(let inner) = outer.content[4],
              case .paragraph(let after) = outer.content[5]
        else { Issue.record("Lost semantic order"); return }
        #expect(paragraph.spans.contains { $0.linkURL?.absoluteString == "https://example.com/link" })
        #expect(inner.summary.plainText == "Nested")
        #expect(after.plainText == "After")
    }

    @Test
    func genericARIAControlAndUnrelatedButtons() throws {
        let blocks = render("""
        <section><p>Prefix</p><h2><button aria-controls="target" aria-expanded="true">Heading<span aria-hidden="true">+</span></button></h2>
        <section id="target"><p>Content</p></section><p>Suffix</p></section>
        <p><button data-id="wrong" title="id='fake'">Ordinary button</button></p>
        """)
        #expect(blocks.count == 4)
        guard case .disclosure(let disclosure) = blocks[1] else { Issue.record("Missing ARIA disclosure"); return }
        #expect(disclosure.summary.plainText == "Heading")
        #expect(disclosure.isInitiallyExpanded)
        guard case .paragraph(let ordinary) = blocks[3] else { Issue.record("Missing ordinary button text"); return }
        #expect(ordinary.plainText == "Ordinary button")
        #expect(ArticleScreenBodyPayloadRenderer.htmlAttribute(named: "id", in: "<button data-id='x' title=\"id='fake'\">") == nil)
    }

    @Test(arguments: [
        "<div><h3><button aria-controls='missing'>Heading</button></h3><p>Available</p></div>",
        "<div><h3><button aria-controls='p'>Heading</button></h3><div id='p'><p>First</p></div><div id='p'><p>Second</p></div></div>",
        "<div><h3><button aria-controls='p'>Heading</button></h3><div id='p'></div></div>",
        "<div><h3><button onclick='loadPanel()'>Heading</button></h3><p>Available</p></div>",
        "<div><h3><button aria-controls='p'>Heading</button></h3><div id='p'><p>Available</p></section></div>",
        "<div><h3><button aria-controls='p'>Heading</button></h3><p>Between</p><div id='p'><p>Available</p></div></div>",
        "<div><h3><button aria-controls='nested'>Heading</button></h3><div><div id='nested'><p>Available</p></div></div></div>"
    ])
    func unsupportedMarkupHasReadableFallback(html: String) {
        let blocks = render(html)
        #expect(blocks.contains { if case .disclosure = $0 { true } else { false } } == false)
        let description = String(describing: blocks)
        #expect(description.contains("Heading"))
        #expect(description.contains("<button") == false)
        #expect(description.contains("aria-controls") == false)
        if html.contains("Available") { #expect(description.contains("Available")) }
        if html.contains("Second") { #expect(description.contains("First") && description.contains("Second")) }
    }

    @Test
    func codeExamplesNeverBecomeDisclosuresOrTargets() throws {
        let example = "<button aria-controls=\"p\">Example</button><div id=\"p\">Panel</div>"
        let escaped = example.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let blocks = render("<pre><code>\(escaped)</code></pre><p>Inline <code>\(escaped)</code></p>" + item())
        #expect(blocks.count == 3)
        guard case .codeBlock(let code) = blocks[0], case .paragraph(let inline) = blocks[1],
              case .disclosure = blocks[2] else { Issue.record("Code was parsed as structure"); return }
        #expect(code == example)
        #expect(inline.plainText == "Inline " + example)
    }

    // Captured simulator markup from https://kinzhal.media/adaptaciya-na-novom-meste-raboty/ on 2026-10-09.
    @Test
    func entirelyEscapedCodePayloadKeepsHTMLExample() throws {
        let payload = "&lt;p&gt;Example &lt;code&gt;&amp;lt;button aria-controls='p'&amp;gt;Toggle&amp;lt;/button&amp;gt;&lt;/code&gt;&lt;/p&gt;"
        let blocks = render(payload)
        guard case .paragraph(let paragraph) = try #require(blocks.first) else { Issue.record("Missing paragraph"); return }
        #expect(paragraph.plainText == "Example <button aria-controls='p'>Toggle</button>")
    }

    @Test
    func capturedKinzhalArticleAccordion() throws {
        let blocks = render(#"""
<div data-wp-context="{ &quot;autoclose&quot;: false, &quot;accordionItems&quot;: [] }" data-wp-interactive="core/accordion" role="group" class="wp-block-accordion is-layout-flow wp-block-accordion-is-layout-flow">
<div data-wp-class--is-open="state.isOpen" data-wp-context="{ &quot;id&quot;: &quot;accordion-item-1&quot;, &quot;openByDefault&quot;: false }" data-wp-init="callbacks.initAccordionItems" data-wp-on-window--hashchange="callbacks.hashChange" class="wp-block-accordion-item is-layout-flow wp-block-accordion-item-is-layout-flow">
<h3 class="wp-block-accordion-heading has-green-background-color has-background"><button aria-expanded="false" aria-controls="accordion-item-1-panel" data-wp-bind--aria-expanded="state.isOpen" data-wp-on--click="actions.toggle" id="accordion-item-1" type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title"><mark style="background-color:rgba(0, 0, 0, 0)" class="has-inline-color has-dark-color">✏️ Ведите свой рабочий конспект</mark></span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span></button></h3>



<div inert aria-labelledby="accordion-item-1" data-wp-bind--inert="!state.isOpen" id="accordion-item-1-panel" role="region" class="wp-block-accordion-panel is-layout-flow wp-block-accordion-panel-is-layout-flow">
<div class="wp-block-group has-gray-background-color has-background"><div class="wp-block-group__inner-container is-layout-constrained wp-block-group-is-layout-constrained">
<p class="wp-block-paragraph">Записывайте:</p>



<ul class="wp-block-list">
<li>внутренние термины;</li>



<li>ссылки на важные документы;</li>



<li>кто за что отвечает;</li>



<li>повторяющиеся шаги;</li>



<li>решения и их причины;</li>



<li>вопросы, которые возникают второй раз.</li>
</ul>
</div></div></div></div></div>
"""#)
        guard case .disclosure(let disclosure) = try #require(blocks.first) else {
            Issue.record("Missing captured article disclosure"); return
        }
        #expect(disclosure.summary.plainText == "✏️ Ведите свой рабочий конспект")
        #expect(disclosure.isInitiallyExpanded == false)
        #expect(disclosure.content.count == 2)
        guard case .list(let list) = disclosure.content[1] else { Issue.record("Missing list"); return }
        #expect(list.items.count == 6)
    }


    @Test
    func detailsRegressionAndRepeatedTitlesKeepSeparateInitialStates() throws {
        let blocks = render("""
        <details open><summary>Same</summary><p>First</p>
        <details><summary>Nested</summary><p>Nested text</p></details></details>
        <details><summary>Same</summary><p>Second</p></details>
        """)
        guard case .disclosure(let first) = blocks[0], case .disclosure(let second) = blocks[1] else { Issue.record("Missing details"); return }
        #expect(first.isInitiallyExpanded)
        #expect(second.isInitiallyExpanded == false)
    }
}
