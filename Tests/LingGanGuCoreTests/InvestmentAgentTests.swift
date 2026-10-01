import XCTest
@testable import LingGanGuCore

final class InvestmentAgentTests: XCTestCase {
    func testAgentReturnsReadOnlyEvaluationForSourceIdea() async throws {
        let provider = MockAIProvider()
        let agent = InvestmentAgent(provider: provider)
        let idea = Idea(rawText: "为自由职业者整理客户反馈")

        let result = try await agent.evaluate(idea)

        XCTAssertEqual(result.ideaID, idea.id)
        XCTAssertEqual(result.verdict, .observe)
        XCTAssertFalse(result.missingEvidence.isEmpty)
        XCTAssertEqual(idea.status, .inbox)
    }

    func testShortlistHonorsMaximum() async {
        let provider = MockAIProvider()
        let agent = InvestmentAgent(provider: provider)
        let ideas = (0..<5).map { Idea(rawText: "想法 \($0)") }

        let results = await agent.shortlist(ideas: ideas, maximum: 3)

        XCTAssertEqual(results.count, 3)
    }
}
