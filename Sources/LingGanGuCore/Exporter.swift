import Foundation

public struct IdeaExportEnvelope: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var exportedAt: Date
    public var ideas: [Idea]
    public var summaries: [Summary]
    public var evaluations: [Evaluation]
    public var conversations: [Conversation]

    public init(
        formatVersion: Int = 2,
        exportedAt: Date = Date(),
        ideas: [Idea],
        summaries: [Summary] = [],
        evaluations: [Evaluation] = [],
        conversations: [Conversation] = []
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.ideas = ideas
        self.summaries = summaries
        self.evaluations = evaluations
        self.conversations = conversations
    }
}

public enum IdeaExporter {
    public static func json(
        _ envelope: IdeaExportEnvelope,
        prettyPrinted: Bool = true
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }

    public static func markdown(
        ideas: [Idea],
        generatedAt: Date = Date()
    ) -> String {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = [
            "# 灵感菇导出",
            "",
            "- 格式版本：2",
            "- 导出时间：\(formatter.string(from: generatedAt))",
            "- 想法数量：\(ideas.count)",
            ""
        ]

        for idea in ideas.sorted(by: { $0.createdAt > $1.createdAt }) {
            lines.append("## \(escapeMarkdown(idea.displayTitle))")
            lines.append("")
            lines.append("- ID：`\(idea.id.uuidString)`")
            lines.append("- 创建时间：\(formatter.string(from: idea.createdAt))")
            lines.append("- 状态：\(idea.status.rawValue)")
            if !idea.tags.isEmpty {
                lines.append("- 标签：\(idea.tags.map { "#\(escapeMarkdown($0))" }.joined(separator: " "))")
            }
            if let topic = idea.aiTopic, !topic.isEmpty {
                lines.append("- AI 主题：\(escapeMarkdown(topic))")
            }
            if !idea.aiSuggestedTags.isEmpty {
                lines.append(
                    "- AI 标签建议：\(idea.aiSuggestedTags.map { "#\(escapeMarkdown($0))" }.joined(separator: " "))"
                )
            }
            lines.append("")
            lines.append(idea.rawText)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func escapeMarkdown(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "#", with: "\\#")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
