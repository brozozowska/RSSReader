import Foundation
import Testing
@testable import RSSReader

@Suite("Article Screen / Reddit HTML Recovery")
@MainActor
struct ArticleScreenRedditRenderingTests {
    @Test func savedPortRadarPayloadRecoversFiveItemsWithInlineStyles() throws {
        let blocks = render(Self.portRadarHTML)
        let lists = blocks.compactMap { block -> ArticleScreenListBlock? in
            if case .list(let list) = block { return list }
            return nil
        }
        #expect(lists.map { $0.items.count } == [5, 2])
        let list = try #require(lists.first)
        #expect(list.items[0].plainText.hasPrefix("📡 Live Dev Port Radar:"))
        #expect(list.items[4].plainText == "⌨️ Global Shortcut: Toggle anywhere with ⌃⌘P.")
        #expect(list.items[1].spans.contains { $0.isCode && $0.text == "SIGKILL -9" })
        #expect(list.items[2].spans.contains { $0.isStrong && $0.text == "Next.js" })
        #expect(blocks.contains(.paragraph(.plainText("What's included:"))) == false) // bold is preserved
        #expect(blocks.contains { if case .paragraph(let text) = $0 { return text.plainText == "What's included:" }; return false })
    }

    @Test func savedSwiftTestingPayloadRecoversCodeWithoutInventingWhitespace() {
        let blocks = render(Self.swiftTestingHTML)
        let code = blocks.compactMap { block -> String? in
            if case .codeBlock(let text) = block { return text }
            return nil
        }
        #expect(code == ["import Testing\n\n@Test(arguments: [ (\"\", 0), (\"cat\", 3), (\"swift\", 5) ]) func characterCounts(input: String, expected: Int) { #expect(input.count == expected) }"])
        #expect(blocks.contains { if case .paragraph(let text) = $0 { return text.plainText.contains("```") }; return false } == false)
        #expect(blocks.contains { if case .paragraph(let text) = $0 { return text.spans.contains { $0.isCode && $0.text == "@Test" } }; return false })
    }

    @Test func recoveryIsRestrictedToRedditMarkdownHTML() {
        for url in ["https://example.com/post", "https://reddit.com.example.com/post"] {
            let article = makeReaderArticleDTO(contentHTML: Self.portRadarHTML, articleURL: url)
            #expect(ArticleScreenBodyPayloadRenderer.recoveringRedditHTML(Self.portRadarHTML, article: article) == Self.portRadarHTML)
        }
        let html = "<p>```swift let x = 1 ```</p>"
        #expect(ArticleScreenBodyPayloadRenderer.recoveringRedditHTML(html, article: makeReaderArticleDTO(articleURL: Self.redditURL)) == html)
    }

    @Test func preservesLiteralCodeExistingBlocksAndAmbiguousProse() {
        for inner in [
            "<p>Use - <strong>one</strong> or - <strong>two</strong>.</p>",
            "<p><strong>Example:</strong> - <strong>one</strong></p>",
            "<pre><code>&lt;p&gt;```swift let x = 1 ```&lt;/p&gt;</code></pre>",
            "<p><code>```swift let x = 1 ```</code></p>",
            "<p>```swift <a href='/guide'>guide</a> ```</p>",
            "<p>```swift unclosed</p><p>Normal paragraph.</p>",
            "<ul><li>Already semantic</li></ul>"
        ] {
            let html = "<div class=\"md\">" + inner + "</div>"
            #expect(ArticleScreenBodyPayloadRenderer.recoveringRedditHTML(html, article: makeReaderArticleDTO(articleURL: Self.redditURL)) == html)
        }
    }

    @Test func preservesUnicodeEntitiesAndActualCodeLineBreaks() {
        let blocks = render("<div class=\"md\"><p>```swift\nlet text = &quot;猫 &amp; 🐈&quot;\n    print(text)\n```</p></div>")
        #expect(blocks == [.codeBlock("let text = \"猫 & 🐈\"\n    print(text)")])
    }

    @Test func listMarkersInsideLinksAndCodeRemainLiteral() throws {
        let blocks = render("<div class=\"md\"><p><strong>Items:</strong> - <strong>First:</strong> <code>x - <strong>literal</strong></code> - <strong>Second:</strong> <a href='/x'>link - <strong>literal</strong></a></p></div>")
        guard case .list(let list) = blocks.last else { Issue.record("Expected list"); return }
        #expect(list.items.count == 2)
        #expect(list.items[0].plainText.contains("literal"))
        #expect(list.items[1].spans.contains { $0.linkURL != nil && $0.text.contains("literal") })
    }

    private func render(_ html: String) -> [ArticleScreenBodyBlock] {
        ArticleScreenContentState(article: makeReaderArticleDTO(
            contentHTML: html, articleURL: Self.redditURL, canonicalURL: nil
        )).body.blocks
    }

    private static let redditURL = "https://www.reddit.com/r/swift/comments/example/post/"
    // Saved Atom payloads read from the simulator on 2026-10-28; no network required.
    private static let portRadarHTML = ##"<!-- SC_OFF --><div class="md"><p>I built a native macOS menu bar utility in Swift/SwiftUI called <strong>PortRadar</strong> to manage listening <code>localhost</code> ports without having to run <code>lsof -i :3000</code> and <code>kill -9</code> in the terminal, and I&#39;m sharing it 100% free and open-source (MIT).</p> <p><strong>What&#39;s included:</strong> - <strong>📡 Live Dev Port Radar:</strong> Shows every listening TCP port right in your menu bar with a live counter badge of active dev servers. - <strong>⚡ 1-Click Kill (<code>SIGTERM</code> / <code>SIGKILL -9</code>):</strong> Free any stuck <code>EADDRINUSE</code> port in a single click. - <strong>🧠 Smart Framework &amp; Stack Detection:</strong> Automatically tags <strong>Next.js</strong>, <strong>Vite</strong>, <strong>Angular</strong>, <strong>Node.js</strong>, <strong>Bun</strong>, <strong>.NET / Kestrel</strong>, <strong>FastAPI / Python</strong>, <strong>Go</strong>, <strong>Rust</strong>, <strong>Docker / OrbStack</strong>, <strong>PostgreSQL</strong>, <strong>Redis</strong>, <strong>MySQL</strong>, <strong>MongoDB</strong>, and <strong>Ollama</strong> — along with live <strong>RAM (MB)</strong>, <strong>CPU %</strong>, and <strong>PID</strong> badges. - <strong>📌 Pinned Watchlist Bar:</strong> Pin your core ports (<code>:3000</code>, <code>:5173</code>, <code>:8080</code>, <code>:5000</code>, <code>:5432</code>, <code>:6379</code>) to the top watchlist bar with live green/grey status indicators and 1-click Open in Browser. - <strong>⌨️ Global Shortcut:</strong> Toggle anywhere with <code>⌃⌘P</code>.</p> <p><strong>Install via Homebrew:</strong> <code>bash brew tap joeystdio/tap brew install --cask portradar </code></p> <ul> <li><strong>Website / Direct DMG Download:</strong> <a href="https://joeystdio.github.io/PortRadar/">https://joeystdio.github.io/PortRadar/</a></li> <li><strong>GitHub Repo:</strong> <a href="https://github.com/joeystdio/PortRadar">https://github.com/joeystdio/PortRadar</a></li> </ul> <p>Hope it saves you some time — happy to hear any feedback or feature ideas!</p> </div><!-- SC_ON --> &#32; submitted by &#32; <a href="https://www.reddit.com/user/Agreeable_Stable_235"> /u/Agreeable_Stable_235 </a> <br/> <span><a href="https://www.reddit.com/r/swift/comments/1xev38j/built_a_native_macos_menu_bar_localhost_dev_port/">[link]</a></span> &#32; <span><a href="https://www.reddit.com/r/swift/comments/1xev38j/built_a_native_macos_menu_bar_localhost_dev_port/">[комментарии]</a></span>"##
    private static let swiftTestingHTML = ##"<!-- SC_OFF --><div class="md"><p>Passing two collections to <code>@Test</code> generates every combination. For example, <code>@Test(arguments: [&quot;cat&quot;, &quot;swift&quot;], [3, 5])</code> creates four cases, including <code>(&quot;cat&quot;, 5)</code> and <code>(&quot;swift&quot;, 3)</code>.</p> <p>That is useful for testing every configuration. For input/expected-output cases, keep each pair together:</p> <p>```swift import Testing</p> <p>@Test(arguments: [ (&quot;&quot;, 0), (&quot;cat&quot;, 3), (&quot;swift&quot;, 5) ]) func characterCounts(input: String, expected: Int) { #expect(input.count == expected) } ```</p> <p>This creates three cases. Swift Testing unpacks each tuple into the function’s two parameters.</p> <p><code>@Test(arguments: zip(inputs, expected))</code> also pairs values, but <a href="https://developer.apple.com/documentation/swift/zip(_:_:">zip stops at the shorter sequence</a>). An accidentally missing expected value can therefore omit a case. A single array of pairs keeps the values together when adding or removing cases.</p> <p><a href="https://developer.apple.com/documentation/testing/parameterizedtesting">Apple’s parameterized testing guide</a> explains combinations and paired arguments.</p> </div><!-- SC_ON --> &#32; submitted by &#32; <a href="https://www.reddit.com/user/pickandplate"> /u/pickandplate </a> <br/> <span><a href="https://www.reddit.com/r/swift/comments/1xdb8o1/swift_testing_keeping_inputs_and_expected_values/">[link]</a></span> &#32; <span><a href="https://www.reddit.com/r/swift/comments/1xdb8o1/swift_testing_keeping_inputs_and_expected_values/">[комментарии]</a></span>"##
}
