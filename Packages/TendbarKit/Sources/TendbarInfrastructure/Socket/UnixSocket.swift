import Darwin
import Foundation

public enum SocketError: Error, Equatable {
    case pathTooLong(String)
    case system(String, Int32)
}

enum SocketAddress {
    static func make(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw SocketError.pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        return address
    }

    static func withSockaddr<T>(_ address: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }
}

enum SocketOptions {
    static func setTimeout(_ fd: Int32, option: Int32, seconds: Double) {
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - seconds.rounded(.down)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    static func disableSigpipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    static func setBlocking(_ fd: Int32, _ blocking: Bool) {
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, blocking ? flags & ~O_NONBLOCK : flags | O_NONBLOCK)
    }
}

public enum UnixSocketClient {
    public static func send(_ data: Data, to path: String, timeout: Double = 1) throws {
        let fd = try connected(to: path, timeout: timeout)
        defer { close(fd) }
        try write(data, to: fd)
    }

    /// Sends a message, then waits up to `wait` seconds for the reply the server writes before it closes.
    public static func request(_ data: Data, to path: String, timeout: Double = 1, wait: Double) throws -> Data {
        let fd = try connected(to: path, timeout: timeout)
        defer { close(fd) }
        try write(data, to: fd)
        shutdown(fd, SHUT_WR)
        SocketOptions.setTimeout(fd, option: SO_RCVTIMEO, seconds: wait)
        return UnixSocketServer.readAll(from: fd)
    }

    private static func connected(to path: String, timeout: Double) throws -> Int32 {
        var address = try SocketAddress.make(path: path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket", errno) }
        SocketOptions.disableSigpipe(fd)
        SocketOptions.setTimeout(fd, option: SO_SNDTIMEO, seconds: timeout)
        let connected = SocketAddress.withSockaddr(&address) { connect(fd, $0, $1) }
        guard connected == 0 else {
            let code = errno
            close(fd)
            throw SocketError.system("connect", code)
        }
        return fd
    }

    private static func write(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, base + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw SocketError.system("write", errno)
                }
                offset += written
            }
        }
    }
}

public final class UnixSocketServer: @unchecked Sendable {
    public static let messageLimit = 1 << 20

    private let path: String
    private let queue = DispatchQueue(label: "pl.dabusoft.tendbar.socket")
    private var source: DispatchSourceRead?

    public init(path: String) {
        self.path = path
    }

    deinit {
        source?.cancel()
    }

    public func start(onMessage: @escaping @Sendable (Data) -> Void) throws {
        try start { data, reply in
            reply.send(nil)
            onMessage(data)
        }
    }

    /// Each message comes with the connection to answer on. It closes once answered, or when the reply is dropped.
    public func start(replying onMessage: @escaping @Sendable (Data, SocketReply) -> Void) throws {
        let fd = try Self.openListener(at: path)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                guard Self.isSameUser(client) else {
                    close(client)
                    continue
                }
                SocketOptions.setBlocking(client, true)
                SocketOptions.disableSigpipe(client)
                SocketOptions.setTimeout(client, option: SO_RCVTIMEO, seconds: 2)
                let data = Self.readAll(from: client)
                let reply = SocketReply(fd: client)
                if data.isEmpty { reply.send(nil) } else { onMessage(data, reply) }
            }
        }
        source.setCancelHandler { [path] in
            close(fd)
            unlink(path)
        }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
    }

    static func openListener(at path: String) throws -> Int32 {
        var address = try SocketAddress.make(path: path)
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket", errno) }
        let bound = SocketAddress.withSockaddr(&address) { bind(fd, $0, $1) }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw SocketError.system("bind", code)
        }
        chmod(path, 0o600)
        guard listen(fd, 32) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw SocketError.system("listen", code)
        }
        SocketOptions.setBlocking(fd, false)
        return fd
    }

    /// The folder is 0700 and the socket 0600; this also refuses a peer of another user (root included).
    static func isSameUser(_ fd: Int32, expected: uid_t = getuid()) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == expected
    }

    static func readAll(from fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while data.count < messageLimit {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer[0..<count])
            } else if count < 0, errno == EINTR {
                continue
            } else {
                break
            }
        }
        return data
    }
}

/// One client connection kept open for an answer. Sending, or dropping the last reference, closes it.
public final class SocketReply: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32?

    init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        if let fd { close(fd) }
    }

    public func send(_ data: Data?) {
        lock.lock()
        defer { lock.unlock() }
        guard let fd else { return }
        self.fd = nil
        if let data, !data.isEmpty {
            SocketOptions.setTimeout(fd, option: SO_SNDTIMEO, seconds: 1)
            data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(fd, base + offset, buffer.count - offset)
                    if written < 0, errno == EINTR { continue }
                    guard written > 0 else { break }
                    offset += written
                }
            }
        }
        close(fd)
    }
}
