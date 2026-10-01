import Foundation

public extension Evaluation {
    /// Shared by standalone exports and the immutable discussion context.
    var markdownReport: String {
        func section(_ name: String, _ values: [String]) -> String {
            "## \(name)\n" + (values.isEmpty ? "无记录" : values.map { "- \($0)" }.joined(separator: "\n"))
        }
        return [
            "# 投资视角评估 · \(verdict.localizedName)",
            "评估编号：\(id.uuidString)\n来源灵感：\(ideaID.uuidString)\n时间：\(createdAt.ISO8601Format())",
            "模型：\(model)\nPrompt：\(promptVersion)\n置信度：\(confidence)（模型自报，不是成功概率）",
            section("原始灵感快照", [sourceRawText ?? "旧记录未保存快照"]),
            section("目标用户", [targetUser]),
            section("判断依据", rationale),
            section("支持理由", supportingArguments ?? []),
            section("反方质疑", opposingArguments ?? []),
            section("获客建议", [distributionPlan ?? "未记录"]),
            section("评分（0—5）", ["痛点 \(scores.painSeverity)，付费可能 \(scores.willingnessToPay)，差异性 \(scores.differentiation)，能力匹配 \(scores.founderFit)，验证容易度 \(scores.validationEase)"]),
            section("风险", risks), section("缺失证据", missingEvidence),
            section("最小验证实验", [smallestExperiment]),
            "此报告为待验证建议，不是市场调查事实；不自动执行或修改灵感。"
        ].joined(separator: "\n\n")
    }
}
