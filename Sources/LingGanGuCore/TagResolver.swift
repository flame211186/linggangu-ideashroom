import Foundation

public enum TagResolver {
    public static func resolve(manualTagText: String, rawText: String) -> [String] {
        let manualTags = parseManualTags(manualTagText)
        return manualTags.isEmpty ? extractHashtags(from: rawText) : manualTags
    }

    public static func parseManualTags(_ text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",，;；#"))
        return Idea.normalize(
            tags: text.components(separatedBy: separators)
        )
    }

    public static func extractHashtags(from text: String) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"#[\p{L}\p{N}_-]+"#
        ) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let tags = expression.matches(in: text, range: range).compactMap { match -> String? in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange].dropFirst())
        }
        return Idea.normalize(tags: tags)
    }
}
