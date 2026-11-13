import Foundation

public enum SessionState: String, Sendable, CaseIterable {
    case idle
    case working
    case needsYou
    case done
    case failed
    case ended
}

public struct TerminalContext: Sendable, Equatable {
    public var program: String?
    /// The app the terminal runs in (`__CFBundleIdentifier`), which also tells VS Code from Cursor.
    public var hostBundleID: String?
    public var itermSessionID: String?
    public var terminalSessionID: String?
    public var tty: String?
    public var configDirectory: String?
    public var weztermPane: String?
    public var weztermSocket: String?
    public var kittyWindowID: String?
    public var kittySocket: String?
    public var tmuxPane: String?
    public var tmuxSocket: String?

    public init(
        program: String? = nil,
        hostBundleID: String? = nil,
        itermSessionID: String? = nil,
        terminalSessionID: String? = nil,
        tty: String? = nil,
        configDirectory: String? = nil,
        weztermPane: String? = nil,
        weztermSocket: String? = nil,
        kittyWindowID: String? = nil,
        kittySocket: String? = nil,
        tmuxPane: String? = nil,
        tmuxSocket: String? = nil
    ) {
        self.program = program
        self.hostBundleID = hostBundleID
        self.itermSessionID = itermSessionID
        self.terminalSessionID = terminalSessionID
        self.tty = tty
        self.configDirectory = configDirectory
        self.weztermPane = weztermPane
        self.weztermSocket = weztermSocket
        self.kittyWindowID = kittyWindowID
        self.kittySocket = kittySocket
        self.tmuxPane = tmuxPane
        self.tmuxSocket = tmuxSocket
    }
}

public struct Session: Sendable, Identifiable, Equatable {
    public var id: String
    public var cwd: String?
    public var transcriptPath: String?
    public var terminal: TerminalContext
    public var state: SessionState
    public var startedAt: Date
    public var updatedAt: Date
    public var unread: Bool
    public var message: String?
    public var preview: String?

    public init(
        id: String,
        cwd: String? = nil,
        transcriptPath: String? = nil,
        terminal: TerminalContext = TerminalContext(),
        state: SessionState = .idle,
        startedAt: Date,
        updatedAt: Date,
        unread: Bool = false,
        message: String? = nil,
        preview: String? = nil
    ) {
        self.id = id
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.terminal = terminal
        self.state = state
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.unread = unread
        self.message = message
        self.preview = preview
    }

    public var folderName: String {
        cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? String(id.prefix(8))
    }

    public var configDirectory: String? {
        terminal.configDirectory
    }
}
