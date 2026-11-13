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
