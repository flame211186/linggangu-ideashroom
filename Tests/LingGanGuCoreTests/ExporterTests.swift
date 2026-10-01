import Foundation
import XCTest
@testable import LingGanGuCore

final class ExporterTests: XCTestCase {
    func testJSONExportContainsNoAPIKeyField() throws {
        let idea = Idea(rawText: "需要安全导出的想法")
        let data = try IdeaExporter.json(
            IdeaExportEnvelope(ideas: [idea])
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains(idea.id.uuidString))
        XCTAssertTrue(text.contains("\"formatVersion\" : 2"))
        XCTAssertFalse(text.lowercased().contains("apikey"))
        XCTAssertFalse(text.lowercased().contains("authorization"))
    }

    func testMarkdownExportEscapesHeadingCharacters() {
        let idea = Idea(
            rawText: "# 一条想法",
            aiTitle: "# 标题",
            tags: ["product"]
        )
        let markdown = IdeaExporter.markdown(
            ideas: [idea],
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(markdown.contains("## \\# 标题"))
        XCTAssertTrue(markdown.contains("#product"))
        XCTAssertTrue(markdown.contains(idea.id.uuidString))
    }
}
