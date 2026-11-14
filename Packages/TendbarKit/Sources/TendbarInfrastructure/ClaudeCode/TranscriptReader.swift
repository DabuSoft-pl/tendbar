import Foundation

public enum TranscriptReader {
    public static let tailBytes = 512 * 1024

    public static func lastAssistantText(at url: URL, tailBytes: Int = tailBytes) -> String? {
        guard let data = tail(of: url, bytes: tailBytes) else { return nil }

        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any]
            else { continue }
            let text = Self.text(of: message["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
    }

    /// Claude Code writes `{"type":"ai-title","aiTitle":"…"}` again and again as the conversation goes on, so the
    /// latest one sits near the end. Lines without the marker are skipped before any JSON is parsed.
    public static func lastTitle(at url: URL, tailBytes: Int = tailBytes) -> String? {
        guard let data = tail(of: url, bytes: tailBytes) else { return nil }
        let marker = Data(#""ai-title""#.utf8)

        for line in data.split(separator: UInt8(ascii: "\n")).reversed() where line.range(of: marker) != nil {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "ai-title",
                  let title = (object["aiTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty
            else { continue }
            return title
        }
        return nil
    }

    private static func tail(of url: URL, bytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil else { return nil }
        return try? handle.readToEnd()
    }

    public static func preview(of text: String, limit: Int = 200) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit - 1)) + "…"
    }

    static func text(of content: Any?) -> String {
        if let text = content as? String { return text }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks
            .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
    }
}
