import Foundation
import TendbarKit

enum EventLog {
    static let sizeLimit: UInt64 = 5 * 1024 * 1024

    static func append(_ data: Data, to url: URL = TendbarPaths.eventLog) {
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber, size.uint64Value > sizeLimit {
            let rotated = url.deletingPathExtension().appendingPathExtension("1.jsonl")
            try? manager.removeItem(at: rotated)
            try? manager.moveItem(at: url, to: rotated)
        }
        if !manager.fileExists(atPath: url.path) {
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data("\n".utf8))
    }
}
