import Foundation
import Testing
import TendbarDomain
@testable import TendbarInfrastructure

@Suite(.timeLimit(.minutes(1))) struct UnixSocketTests {
    private func temporarySocketPath() -> String {
        "/tmp/tendbar-test-\(UUID().uuidString.prefix(8)).sock"
    }

    @Test func deliversMessagesFromClients() async throws {
        let path = temporarySocketPath()
        let server = UnixSocketServer(path: path)
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        try server.start { continuation.yield($0) }
        defer { server.stop() }

        try UnixSocketClient.send(Data("first".utf8), to: path)
        try UnixSocketClient.send(Data("second".utf8), to: path)

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        #expect(first.map { String(decoding: $0, as: UTF8.self) } == "first")
        #expect(second.map { String(decoding: $0, as: UTF8.self) } == "second")
    }

    @Test func deliversLargeMessages() async throws {
        let path = temporarySocketPath()
        let server = UnixSocketServer(path: path)
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        try server.start { continuation.yield($0) }
        defer { server.stop() }
        let payload = Data(repeating: 0x61, count: 200_000)

        try UnixSocketClient.send(payload, to: path)

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == payload)
    }

    @Test func socketIsPrivateToUser() throws {
        let path = temporarySocketPath()
        let server = UnixSocketServer(path: path)
        try server.start { _ in }
        defer { server.stop() }

        let attributes = try FileManager.default.attributesOfItem(atPath: path)

        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func clientFailsWhenNobodyListens() {
        #expect(throws: SocketError.self) {
            try UnixSocketClient.send(Data("x".utf8), to: temporarySocketPath())
        }
    }

    @Test func rejectsTooLongPath() {
        let path = "/tmp/" + String(repeating: "a", count: 200) + ".sock"

        #expect(throws: SocketError.pathTooLong(path)) {
            try UnixSocketClient.send(Data("x".utf8), to: path)
        }
    }
}
