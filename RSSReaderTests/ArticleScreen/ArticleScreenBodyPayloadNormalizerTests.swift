import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Article Screen / Content Rendering / Body Payload Normalizer")
@MainActor
struct ArticleScreenBodyPayloadNormalizerTests {
    @Test
    func articleScreenBodyPayloadNormalizerClassifiesEscapedHTMLAsHTML() throws {
        let payload = try #require(
            ArticleScreenBodyPayloadNormalizer.normalize(
                """
                &lt;p&gt;Это уже другой уровень&lt;/p&gt;
                &lt;p&gt;Сообщение &lt;a href=&quot;https://thecode.media/article&quot;&gt;Создатели Flipper Zero&lt;/a&gt; появились сначала&lt;/p&gt;
                """,
                preferredKind: .plainText
            )
        )

        #expect(payload.kind == .html)
        #expect(payload.value.contains("<p>Это уже другой уровень</p>"))
        #expect(payload.value.contains(#"<a href="https://thecode.media/article">Создатели Flipper Zero</a>"#))
    }

    @Test
    func articleScreenBodyPayloadNormalizerDecodesNumericEntities() throws {
        let payload = try #require(
            ArticleScreenBodyPayloadNormalizer.normalize(
                "Зарплата &#8381; и аванс &#x20BD;",
                preferredKind: .plainText
            )
        )

        #expect(payload.kind == .plainText)
        #expect(payload.value == "Зарплата ₽ и аванс ₽")
    }

    @Test
    func articleScreenBodyPayloadNormalizerClassifiesAbbreviationMarkupAsHTML() throws {
        let rawPayload = try #require(
            ArticleScreenBodyPayloadNormalizer.normalize(
                #"Read <abbr title="Continuous Integration">CI</abbr> safely."#,
                preferredKind: .plainText
            )
        )
        let repeatedlyEscapedPayload = try #require(
            ArticleScreenBodyPayloadNormalizer.normalize(
                #"Read &amp;lt;abbr title=&amp;quot;Continuous Integration&amp;quot;&amp;gt;CI&amp;lt;/abbr&amp;gt; safely."#,
                preferredKind: .plainText
            )
        )

        #expect(rawPayload.kind == .html)
        #expect(repeatedlyEscapedPayload.kind == .html)
        #expect(repeatedlyEscapedPayload.value == rawPayload.value)
    }

    @Test
    func articleScreenBodyPayloadNormalizerDoesNotTreatComparisonsAsHTML() throws {
        let payload = try #require(
            ArticleScreenBodyPayloadNormalizer.normalize(
                "Bounds stay 2 < 3 and 5 > 4.",
                preferredKind: .plainText
            )
        )

        #expect(payload.kind == .plainText)
        #expect(payload.value == "Bounds stay 2 < 3 and 5 > 4.")
    }
}
