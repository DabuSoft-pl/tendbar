import Foundation

public enum TendbarPaths {
    public static let socketOverrideVariable = "TENDBAR_SOCKET"

    public static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tendbar", isDirectory: true)
    }

    public static var socket: URL {
        supportDirectory.appendingPathComponent("tendbar.sock")
    }

    public static var eventLog: URL {
        supportDirectory.appendingPathComponent("events.jsonl")
    }

    public static var sessions: URL {
        supportDirectory.appendingPathComponent("sessions.json")
    }

    public static var usage: URL {
        supportDirectory.appendingPathComponent("usage.json")
    }

    public static func socketPath(environment: [String: String]) -> String {
        environment[socketOverrideVariable] ?? socket.path
    }

    public static func writePrivately(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
