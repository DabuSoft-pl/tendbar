import Foundation
import TendbarApplication

/// Reads reply previews and titles only from Claude Code transcripts. The path arrives over the socket, so anything else
/// (a file in Documents, a symlink out of `projects/`) is refused instead of read on the sender's behalf.
public struct FileTranscriptReader: TranscriptReading {
    private let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func lastReplyPreview(at path: String) async -> String? {
        guard let url = Self.transcriptURL(path, home: home) else { return nil }
        return await Task.detached(priority: .utility) {
            TranscriptParser.lastAssistantText(at: url).map { TranscriptParser.preview(of: $0) }
        }.value
    }

    public func title(at path: String) async -> String? {
        guard let url = Self.transcriptURL(path, home: home) else { return nil }
        return await Task.detached(priority: .utility) {
            TranscriptParser.lastTitle(at: url).map { TranscriptParser.preview(of: $0, limit: 80) }
        }.value
    }

    /// `~/.claude*/projects/…/*.jsonl` after resolving symlinks, or nil.
    static func transcriptURL(_ path: String, home: URL) -> URL? {
        guard path.hasPrefix("/") else { return nil }
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let base = home.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let components = resolved.pathComponents
        guard resolved.pathExtension == "jsonl",
              components.count > base.count + 3,
              Array(components.prefix(base.count)) == base,
              components[base.count].hasPrefix(".claude"),
              components[base.count + 1] == "projects"
        else { return nil }
        return resolved
    }
}
