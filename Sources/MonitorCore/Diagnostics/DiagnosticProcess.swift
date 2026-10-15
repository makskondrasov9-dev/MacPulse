import Darwin
import Foundation

/// Bounded, cancellable command execution without a shell or an undrained pipe.
/// A separate read descriptor allows incremental delivery while the child writes.
public enum DiagnosticProcess {
    public struct Output: Sendable { public let data: Data; public let status: Int32 }
    public static func run(_ executable: String, arguments: [String], timeout: TimeInterval,
                           maximumBytes: Int = 1_048_576,
                           line: @Sendable (String) async -> Void = { _ in }) async throws -> Output {
        try Task.checkCancellation()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-command-\(UUID().uuidString)")
        let fd = open(path.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw DiagnosticError.failed("Cannot create diagnostic output file") }
        let writer = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? writer.close(); try? FileManager.default.removeItem(at: path) }
        let reader = try FileHandle(forReadingFrom: path)
        defer { try? reader.close() }
        guard unlink(path.path) == 0 else { throw DiagnosticError.failed("Cannot secure diagnostic output file") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = writer; process.standardError = writer
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"; environment["LANG"] = "C"
        process.environment = environment
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        var data = Data(), pending = Data()
        do {
            while true {
                try Task.checkCancellation()
                let running = process.isRunning
                let chunk = try reader.read(upToCount: 65_536) ?? Data()
                guard data.count + chunk.count <= maximumBytes else { throw DiagnosticError.failed("Diagnostic output exceeded limit") }
                data.append(chunk); pending.append(chunk)
                while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                    let text = String(decoding: pending[..<end], as: UTF8.self)
                    pending.removeSubrange(...end)
                    if !text.isEmpty { await line(text) }
                }
                if !running && chunk.isEmpty { break }
                if ProcessInfo.processInfo.systemUptime > deadline { throw DiagnosticError.failed("Diagnostic command timed out") }
                try await Task.sleep(for: .milliseconds(100))
            }
            if !pending.isEmpty { await line(String(decoding: pending, as: UTF8.self)) }
            return Output(data: data, status: process.terminationStatus)
        } catch {
            if process.isRunning { process.terminate() }
            let grace = ProcessInfo.processInfo.systemUptime + 2
            while process.isRunning && ProcessInfo.processInfo.systemUptime < grace {
                await Task.detached { try? await Task.sleep(for: .milliseconds(25)) }.value
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            while process.isRunning { await Task.detached { try? await Task.sleep(for: .milliseconds(20)) }.value }
            throw error
        }
    }
}
