import Foundation

/// Presentation only. Stored model output and source IDs remain unchanged.
public enum ChatCitationDisplay {
    public static func render(_ content: String, allowedIDs: [UUID], streaming: Bool = false) -> AttributedString {
        var text = content
        // Normalize provider-inserted line breaks in source identifiers.
        let wrappedID = try! NSRegularExpression(pattern: #"[0-9a-fA-F]{8}\s*-\s*[0-9a-fA-F]{4}\s*-\s*[0-9a-fA-F]{4}\s*-\s*[0-9a-fA-F]{4}\s*-\s*[0-9a-fA-F]{12}"#)
        for match in wrappedID.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let compact = text[range].filter { !$0.isWhitespace }
            text.replaceSubrange(range, with: compact)
        }
        // Plain readable headings; do not expose Markdown syntax in the native text view.
        text = text.replacingOccurrences(of: #"(?m)^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
        if streaming, let open = text.lastIndex(of: "[") {
            let suffix = text[text.index(after: open)...]
            if !suffix.contains("]"), suffix.count <= 36,
               suffix.allSatisfy({ $0.isHexDigit || $0 == "-" || $0.isWhitespace }) {
                text = String(text[..<open])
            }
        }
        let regex = try! NSRegularExpression(pattern: #"(?:\[\s*)?([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?:\s*\])?"#)
        var result = AttributedString()
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text),
                  let idRange = Range(match.range(at: 1), in: text),
                  let id = UUID(uuidString: String(text[idRange])) else { continue }
            result.append(AttributedString(String(text[cursor..<range.lowerBound])))
            if let index = allowedIDs.firstIndex(of: id) {
                var label = AttributedString("[来源 \(index + 1)]")
                label.link = URL(string: "linggangu-source://\(id.uuidString)")
                result.append(label)
            } else {
                result.append(AttributedString("[来源不可用]"))
            }
            cursor = range.upperBound
        }
        result.append(AttributedString(String(text[cursor...])))
        return result
    }
}
