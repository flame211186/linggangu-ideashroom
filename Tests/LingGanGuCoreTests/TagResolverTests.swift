import XCTest
@testable import LingGanGuCore

final class TagResolverTests: XCTestCase {
    func testManualTagsTakePrecedenceOverBodyHashtags() {
        let tags = TagResolver.resolve(
            manualTagText: "#产品, AI 产品",
            rawText: "正文里的 #设计 和 #实验"
        )
        XCTAssertEqual(tags, ["产品", "ai"])
    }

    func testEmptyManualTagsExtractUnicodeHashtagsWithoutChangingBody() {
        let body = "想做一个 #灵感整理 工具，也看看 #AI-product 和重复的 #灵感整理"
        let tags = TagResolver.resolve(manualTagText: "  ", rawText: body)
        XCTAssertEqual(tags, ["灵感整理", "ai-product"])
        XCTAssertEqual(
            body,
            "想做一个 #灵感整理 工具，也看看 #AI-product 和重复的 #灵感整理"
        )
    }

    func testManualParserAcceptsSpacesCommasAndHashMarks() {
        XCTAssertEqual(
            TagResolver.parseManualTags("#产品 灵感，AI,产品"),
            ["产品", "灵感", "ai"]
        )
    }
}
