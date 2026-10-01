import Foundation

public actor MockAIProvider: AIProvider {
    public let modelName = "mock-linggangu"
    public var simulatedDelay: Duration

    public init(simulatedDelay: Duration = .zero) {
        self.simulatedDelay = simulatedDelay
    }

    public func testConnection() async throws {
        try await delayIfNeeded()
    }

    public func annotate(idea: Idea) async throws -> AIAnnotation {
        try await delayIfNeeded()
        let title = String(idea.displayTitle.prefix(24))
        return AIAnnotation(title: title, tags: ["待整理"], topic: "灵感")
    }

    public func summarize(ideas: [Idea], scope: SummaryScope) async throws -> Summary {
        try await delayIfNeeded()
        return Summary(
            scope: scope,
            content: SummaryContent(
                themes: ["模拟主题"],
                repeatedDirections: ideas.count > 1 ? ["存在多条可比较想法"] : [],
                newDirections: ideas.map(\.displayTitle),
                contradictions: [],
                openQuestions: ["下一步最小验证是什么？"],
                mergeSuggestions: [],
                actions: ["选择一条想法完成一次最小验证"]
            ),
            sourceIdeaIDs: ideas.map(\.id),
            model: modelName,
            promptVersion: PromptCatalog.summaryVersion
        )
    }

    public func chat(turns: [AIChatTurn], ideas: [Idea]) async throws -> String {
        try await delayIfNeeded()
        let latestQuestion = turns.last?.content ?? ""
        let citations = ideas.prefix(3).map { "[\($0.id.uuidString)]" }.joined(separator: " ")
        return "模拟回答：\(latestQuestion) \(citations)"
    }

    public nonisolated func chatStream(
        turns: [AIChatTurn],
        ideas: [Idea]
    ) -> AsyncThrowingStream<String, Error> {
        let latestQuestion = turns.last?.content ?? ""
        let citations = ideas.prefix(3).map { "[\($0.id.uuidString)]" }.joined(separator: " ")
        let chunks = ["模拟回答：", latestQuestion, " ", citations]
        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks where !chunk.isEmpty {
                    try Task.checkCancellation()
                    continuation.yield(chunk)
                    try await Task.sleep(for: .milliseconds(20))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func evaluate(idea: Idea) async throws -> Evaluation {
        try await delayIfNeeded()
        return Evaluation(
            ideaID: idea.id,
            verdict: .observe,
            scores: EvaluationScores(
                painSeverity: 3,
                willingnessToPay: 2,
                differentiation: 3,
                founderFit: 3,
                validationEase: 4
            ),
            targetUser: "需要进一步确认的目标用户",
            rationale: ["想法具备可测试的基本假设"],
            risks: ["当前没有真实用户证据"],
            missingEvidence: ["访谈或行为数据", "付费意愿"],
            confidence: 0.35,
            smallestExperiment: "用一天制作说明页并访谈 3 名潜在用户",
            model: modelName,
            promptVersion: PromptCatalog.investorVersion,
            supportingArguments: ["可以用低成本原型测试"],
            opposingArguments: ["尚无真实付费证据"],
            distributionPlan: "建议邀请三名目标用户进行访谈",
            sourceRawText: idea.rawText
        )
    }

    private func delayIfNeeded() async throws {
        if simulatedDelay > .zero {
            try await Task.sleep(for: simulatedDelay)
        }
    }
}
