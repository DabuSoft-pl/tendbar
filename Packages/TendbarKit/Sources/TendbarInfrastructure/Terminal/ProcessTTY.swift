import Darwin

public enum ProcessTTY {
    public static func controllingTTY(startingAt pid: pid_t = getppid(), maxDepth: Int = 8) -> String? {
        var current = pid
        for _ in 0..<maxDepth {
            guard current > 1, let info = processInfo(current) else { return nil }
            let device = info.kp_eproc.e_tdev
            if device != -1, let name = devname(device, S_IFCHR) {
                let value = String(cString: name)
                if value != "??" { return "/dev/" + value }
            }
            current = info.kp_eproc.e_ppid
        }
        return nil
    }

    static func processInfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}

/// A Claude Code process as the hook helper finds it among its parents.
public struct ClaudeProcess: Sendable, Equatable {
    public var id: Int32
    public var startedAt: Double

    public init(id: Int32, startedAt: Double) {
        self.id = id
        self.startedAt = startedAt
    }

    /// Claude Code runs a hook through a shell, so the first parent that is not a shell is Claude Code itself.
    public static func parent(of pid: pid_t = getppid(), maxDepth: Int = 4) -> ClaudeProcess? {
        var current = pid
        for _ in 0..<maxDepth {
            guard current > 1, let info = ProcessTTY.processInfo(current) else { return nil }
            if !shells.contains(ProcessTTY.name(info)) {
                return ClaudeProcess(id: current, startedAt: ProcessTTY.startTime(info))
            }
            current = info.kp_eproc.e_ppid
        }
        return nil
    }

    static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env", "tendbar-hook"]
}

extension ProcessTTY {
    static func name(_ info: kinfo_proc) -> String {
        var comm = info.kp_proc.p_comm
        return withUnsafeBytes(of: &comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    static func startTime(_ info: kinfo_proc) -> Double {
        let time = info.kp_proc.p_starttime
        return Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
    }

    /// Whether the process still runs and is the same one, not a new process that reused its id.
    public static func isRunning(_ pid: Int32, startedAt: Double?) -> Bool {
        guard let info = processInfo(pid), info.kp_proc.p_pid == pid else { return false }
        guard let startedAt else { return true }
        return abs(startTime(info) - startedAt) < 1
    }

    /// Whether a Claude Code process still runs on the terminal, for sessions recorded before their process was.
    public static func hasClaude(on tty: String) -> Bool? {
        var status = stat()
        guard stat(tty, &status) == 0 else { return false }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_TTY, Int32(bitPattern: UInt32(status.st_rdev))]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0 else { return nil }
        var list = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 8)
        size = list.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &list, &size, nil, 0) == 0 else { return nil }
        let count = size / MemoryLayout<kinfo_proc>.stride
        return list.prefix(count).contains { ["claude", "node"].contains(name($0)) }
    }
}
