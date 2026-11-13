import Foundation
import TendbarDomain
import TendbarInfrastructure

let environment = ProcessInfo.processInfo.environment
let arguments = CommandLine.arguments
let isStatusLine = arguments.contains(HookInstaller.statusLineFlag)
let input = FileHandle.standardInput.readDataToEndOfFile()
let envelope = HookEnvelope(
    sentAt: Date(),
    terminal: .capture(
        environment: environment,
        tty: ProcessTTY.controllingTTY(),
        process: isStatusLine ? nil : ClaudeProcess.parent()
    ),
    raw: HookRedaction.redact(input, statusLine: isStatusLine),
    channel: isStatusLine ? HookEnvelope.statusLineChannel : nil
)

let socketPath = TendbarPaths.socketPath(environment: environment)

// A permission prompt waits for Tendbar's answer from a banner. Without one the hook prints nothing and the
// terminal prompt decides, as it does meanwhile anyway.
if !isStatusLine, let permission = PermissionRecord(hookInput: input) {
    var asking = envelope
    asking.permission = permission
    if let data = try? HookEnvelope.encoder.encode(asking),
       let answer = try? UnixSocketClient.request(data, to: socketPath, wait: HookInstaller.permissionWaitSeconds),
       let decision = PermissionAnswer.decode(answer) {
        FileHandle.standardOutput.write(PermissionAnswer.hookOutput(decision))
    }
    exit(0)
}

if let data = try? HookEnvelope.encoder.encode(envelope) {
    try? UnixSocketClient.send(data, to: socketPath)
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
