import XCTest
@testable import LingGanGuCore

final class ModelsTests: XCTestCase {
    func testIdeaNormalizesTextAndTags() {
        let idea = Idea(
            rawText: "  做一个灵感组件  \n",
            tags: ["#Product", " product ", "", "#AI"]
        )

        XCTAssertEqual(idea.rawText, "做一个灵感组件")
        XCTAssertEqual(idea.tags, ["product", "ai"])
        XCTAssertTrue(idea.isValid)
        XCTAssertEqual(idea.displayTitle, "做一个灵感组件")
    }

    func testSummaryScopeRoundTrip() throws {
        let original = SummaryScope.dateRange(
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SummaryScope.self, from: data)
        XCTAssertEqual(decoded, original)

        let topic = SummaryScope.topic("产品验证")
        let topicData = try JSONEncoder().encode(topic)
        XCTAssertEqual(
            try JSONDecoder().decode(SummaryScope.self, from: topicData),
            topic
        )
    }

    func testOldConversationMessageDefaultsToComplete() throws {
        let id = UUID()
        let json = """
        {
          "id":"\(id.uuidString)",
          "role":"assistant",
          "content":"旧回复",
          "createdAt":0,
          "sourceIdeaIDs":[]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let message = try decoder.decode(
            ConversationMessage.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(message.deliveryState, .complete)
    }

    func testEvaluationClampsScoresAndConfidence() {
        let scores = EvaluationScores(
            painSeverity: -2,
            willingnessToPay: 2,
            differentiation: 3,
            founderFit: 4,
            validationEase: 9
        )
        let evaluation = Evaluation(
            ideaID: UUID(),
            verdict: .observe,
            scores: scores,
            targetUser: "创作者",
            rationale: [],
            risks: [],
            missingEvidence: [],
            confidence: 2,
            smallestExperiment: "访谈",
            model: "mock",
            promptVersion: "v1"
        )

        XCTAssertEqual(scores.painSeverity, 0)
        XCTAssertEqual(scores.validationEase, 5)
        XCTAssertEqual(evaluation.confidence, 1)
    }
}
