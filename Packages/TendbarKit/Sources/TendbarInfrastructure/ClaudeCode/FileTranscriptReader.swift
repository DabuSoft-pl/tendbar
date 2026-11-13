import Foundation
import TendbarApplication

public struct FileTranscriptReader: TranscriptReading {
    public init() {}

    public func lastReplyPreview(at path: String) async -> String? {
        await Task.detached(priority: .utility) {
            TranscriptReader.lastAssistantText(at: URL(fileURLWithPath: path)).map { TranscriptReader.preview(of: $0) }
        }.value
    }
}
