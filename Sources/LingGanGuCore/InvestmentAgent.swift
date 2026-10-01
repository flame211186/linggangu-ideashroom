import Foundation

public struct InvestmentAgent: Sendable {
    private let provider: any AIProvider

    public init(provider: any AIProvider) {
        self.provider = provider
    }

    public func evaluate(_ idea: Idea) async throws -> Evaluation {
        guard idea.isValid else {
            throw AIProviderError.invalidConfiguration("想法内容不能为空")
        }
        try Task.checkCancellation()
        var result = try await provider.evaluate(idea: idea)
        try Task.checkCancellation()
        guard result.ideaID == idea.id else {
            throw AIProviderError.decoding("评估结果引用了错误的 Idea ID")
        }
        guard !result.smallestExperiment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !result.targetUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.supportingArguments?.isEmpty == false,
              result.opposingArguments?.isEmpty == false,
              result.distributionPlan?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              result.confidence.isFinite, (0...1).contains(result.confidence) else {
            throw AIProviderError.decoding("评估必须包含目标用户、正反论据、获客建议、最小实验和有效置信度")
        }
        result.sourceRawText = idea.rawText
        result.schemaVersion = 2
        return result
    }

    public func shortlist(
        ideas: [Idea],
        maximum: Int = 3
    ) async -> [(idea: Idea, evaluation: Result<Evaluation, Error>)] {
        let safeMaximum = min(max(maximum, 1), 10)
        var results: [(Idea, Result<Evaluation, Error>)] = []

        for idea in ideas where idea.status != .archived {
            if Task.isCancelled { break }
            do {
                let evaluation = try await evaluate(idea)
                results.append((idea, .success(evaluation)))
            } catch {
                results.append((idea, .failure(error)))
            }
        }

        return Array(
            results.sorted { left, right in
                switch (left.1, right.1) {
                case (.success(let lhs), .success(let rhs)):
                    if lhs.verdict != rhs.verdict {
                        return Self.verdictRank(lhs.verdict) < Self.verdictRank(rhs.verdict)
                    }
                    if lhs.scores.average != rhs.scores.average {
                        return lhs.scores.average > rhs.scores.average
                    }
                    return lhs.confidence > rhs.confidence
                case (.success, .failure):
                    return true
                case (.failure, .success):
                    return false
                case (.failure, .failure):
                    return left.0.createdAt > right.0.createdAt
                }
            }.prefix(safeMaximum)
        )
    }

    public static func verdictRank(_ verdict: InvestmentVerdict) -> Int {
        switch verdict {
        case .validateNow: 0
        case .observe: 1
        case .archive: 2
        }
    }
}
