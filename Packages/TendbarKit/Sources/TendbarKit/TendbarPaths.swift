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

    public static func socketPath(environment: [String: String]) -> String {
        environment[socketOverrideVariable] ?? socket.path
    }
}
