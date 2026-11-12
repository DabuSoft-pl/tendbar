import Foundation
import TendbarKit

let environment = ProcessInfo.processInfo.environment
let input = FileHandle.standardInput.readDataToEndOfFile()
let envelope = HookEnvelope(
    sentAt: Date(),
    terminal: .capture(environment: environment, tty: ProcessTTY.controllingTTY()),
    raw: String(decoding: input, as: UTF8.self)
)

if let data = try? HookEnvelope.encoder.encode(envelope) {
    try? UnixSocketClient.send(data, to: TendbarPaths.socketPath(environment: environment))
}

exit(0)
