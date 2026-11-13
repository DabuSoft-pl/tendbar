import Foundation

public struct CommandResult: Equatable, Sendable {
    public var status: Int32
    public var output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }

    public var succeeded: Bool { status == 0 }
}

/// Runs a terminal's command line tool; a test double replaces it.
public protocol CommandRunning: Sendable {
    func run(_ command: TerminalCommand) -> CommandResult
}

/// Runs a command directly (no shell) and gives up after a short timeout, so a hung tool cannot freeze the app.
public struct ProcessCommandRunner: CommandRunning {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 2) {
        self.timeout = timeout
    }

    public func run(_ command: TerminalCommand) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: "")
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return CommandResult(status: -1, output: "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

extension TmuxTarget {
    /// Selects the pane and returns the TTY of a tmux client that now shows it, if any.
    public func select(using runner: CommandRunning) -> String? {
        for command in selectCommands { _ = runner.run(command) }
        let session = runner.run(sessionCommand)
        let name = session.succeeded ? Self.lines(session.output).first : nil
        if let client = Self.lines(runner.run(clientsCommand(session: name)).output).first {
            return client
        }
        guard let client = Self.lines(runner.run(clientsCommand(session: nil)).output).first else { return nil }
        return runner.run(switchCommand(client: client)).succeeded ? client : nil
    }

    static func lines(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
