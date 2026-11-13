import Foundation
import TendbarKit

let environment = ProcessInfo.processInfo.environment
let arguments = CommandLine.arguments
let isStatusLine = arguments.contains(HookInstaller.statusLineFlag)
let input = FileHandle.standardInput.readDataToEndOfFile()
let envelope = HookEnvelope(
    sentAt: Date(),
    terminal: .capture(environment: environment, tty: ProcessTTY.controllingTTY()),
    raw: String(decoding: input, as: UTF8.self),
    channel: isStatusLine ? HookEnvelope.statusLineChannel : nil
)

if let data = try? HookEnvelope.encoder.encode(envelope) {
    try? UnixSocketClient.send(data, to: TendbarPaths.socketPath(environment: environment))
}

guard isStatusLine,
      let flag = arguments.firstIndex(of: HookInstaller.nextFlag),
      arguments.indices.contains(flag + 1),
      let data = Data(base64Encoded: arguments[flag + 1]),
      let next = String(data: data, encoding: .utf8)
else { exit(0) }

let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/sh")
process.arguments = ["-c", next]
let stdin = Pipe()
process.standardInput = stdin
process.standardOutput = FileHandle.standardOutput
process.standardError = FileHandle.standardError
do {
    try process.run()
} catch {
    exit(1)
}
try? stdin.fileHandleForWriting.write(contentsOf: input)
try? stdin.fileHandleForWriting.close()
process.waitUntilExit()
exit(process.terminationStatus)
