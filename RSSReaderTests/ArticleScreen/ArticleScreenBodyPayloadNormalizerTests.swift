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
}
