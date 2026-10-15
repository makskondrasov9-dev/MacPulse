import Accelerate
import Darwin
import Foundation
import Metal

public enum DiagnosticError: Error, LocalizedError, Sendable {
    case failed(String)
    public var errorDescription: String? { if case .failed(let message) = self { return message }; return nil }
}

public struct DiskBenchmarkResult: Sendable {
    public let bytes: Int
    public let writeMBps: Double
    public let readMBps: Double
}

public enum BenchmarkEngine {
    /// A single private, unlinked file: cancellation, failure and process exit all release it.
    /// This bypasses the OS page cache, not the SSD controller's own cache.
    public static func disk(bytes: Int = 1_000_000_000, directory: URL = FileManager.default.temporaryDirectory,
                            progress: @Sendable (Double) async -> Void = { _ in }) async throws -> DiskBenchmarkResult {
        guard bytes > 0, bytes <= 1_000_000_000 else { throw DiagnosticError.failed("Invalid benchmark size") }
        try Task.checkCancellation()
        let path = directory.appendingPathComponent("MacPulse-benchmark-\(UUID().uuidString)").path
        let fd = open(path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw posixError() }
        defer { close(fd) }
        guard unlink(path) == 0 else { throw posixError() }
        var space = statfs()
        guard fstatfs(fd, &space) == 0 else { throw posixError() }
        guard UInt64(space.f_bavail) * UInt64(space.f_bsize) > UInt64(bytes) + 512_000_000 else {
            throw DiagnosticError.failed("Not enough free disk space")
        }
        guard fcntl(fd, F_NOCACHE, 1) == 0 else { throw posixError() }
        var buffer = [UInt8](repeating: 0, count: min(bytes, 4 * 1024 * 1024))
        buffer.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, $0.count) }
        let start = ProcessInfo.processInfo.systemUptime
        var done = 0
        while done < bytes {
            try Task.checkCancellation()
            let size = min(buffer.count, bytes - done)
            let count = buffer.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, size) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw posixError() }
            done += count
            await progress(Double(done) / Double(bytes) * 0.5)
        }
        try Task.checkCancellation()
        guard fcntl(fd, F_FULLFSYNC) == 0 else { throw posixError() }
        let writeTime = ProcessInfo.processInfo.systemUptime - start
        guard lseek(fd, 0, SEEK_SET) == 0 else { throw posixError() }
        let readStart = ProcessInfo.processInfo.systemUptime
        done = 0
        while done < bytes {
            try Task.checkCancellation()
            let size = min(buffer.count, bytes - done)
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, size) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw DiagnosticError.failed("Incomplete benchmark read") }
            done += count
            await progress(0.5 + Double(done) / Double(bytes) * 0.5)
        }
        try Task.checkCancellation()
        return DiskBenchmarkResult(bytes: bytes, writeMBps: Double(bytes) / max(writeTime, 0.000001) / 1e6,
            readMBps: Double(bytes) / max(ProcessInfo.processInfo.systemUptime - readStart, 0.000001) / 1e6)
    }

    private static func posixError() -> DiagnosticError { .failed(String(cString: strerror(errno))) }

    /// Independent bounded vector workloads, one per logical CPU; yield between batches.
    public static func cpu(seconds: Int, workers: Int = CPUCapabilities.maximumWorkers,
                           progress: @escaping @Sendable (CPUProgress) async -> Void = { _ in }) async throws -> UInt64 {
        guard [15, 30, 60].contains(seconds) else { throw DiagnosticError.failed("Invalid test duration") }
        guard (1...CPUCapabilities.maximumWorkers).contains(workers) else { throw DiagnosticError.failed("Invalid worker count") }
        let accumulator = CPUProgressAccumulator(workers: workers)
        let deadline = ProcessInfo.processInfo.systemUptime + Double(seconds)
        return try await withThrowingTaskGroup(of: UInt64.self) { group in
            for worker in 0..<workers {
                group.addTask(priority: .utility) {
                    var values = [Float](repeating: 0.5, count: 65_536)
                    var output = values
                    var count: UInt64 = 0
                    var lastReport = ProcessInfo.processInfo.systemUptime
                    while ProcessInfo.processInfo.systemUptime < deadline {
                        try Task.checkCancellation()
                        if count % 256 == 0 && ProcessInfo.processInfo.thermalState == .critical {
                            throw DiagnosticError.failed("Stopped: critical thermal state")
                        }
                        values.withUnsafeBufferPointer { input in
                            output.withUnsafeMutableBufferPointer { result in
                                var scale: Float = 0.9999, offset: Float = 0.0001
                                vDSP_vsmsa(input.baseAddress!, 1, &scale, &offset, result.baseAddress!, 1, vDSP_Length(values.count))
                            }
                        }
                        swap(&values, &output)
                        // Keep non-zero operands to avoid denormal/zero-only workloads.
                        for i in stride(from: 0, to: values.count, by: 64) { values[i] = 0.9999 }
                        count += 1
                        if count % 64 == 0 && ProcessInfo.processInfo.systemUptime - lastReport >= 0.5 {
                            lastReport = ProcessInfo.processInfo.systemUptime
                            if let sample = await accumulator.record(worker: worker, count: count) { await progress(sample) }
                        }
                        await Task.yield()
                    }
                    return count
                }
            }
            var total: UInt64 = 0
            for try await count in group { total += count }
            return total
        }
    }

    public static func gpu(seconds: Int = 15) async throws -> UInt64 {
        guard [15, 30, 60].contains(seconds), let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { throw DiagnosticError.failed("Metal is unavailable") }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void stress(device float *out [[buffer(0)]], uint i [[thread_position_in_grid]]) {
            float x = float(i % 997) * 0.001f + 0.1f;
            for (uint j=0; j<256; ++j) { x = sin(x) * 0.999f + 0.1f; }
            out[i] = x;
        }
        """
        let library = try await device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "stress"),
              let buffer = device.makeBuffer(length: 65_536 * MemoryLayout<Float>.size, options: .storageModeShared) else {
            throw DiagnosticError.failed("Metal allocation failed")
        }
        let pipeline = try await device.makeComputePipelineState(function: function)
        let deadline = ProcessInfo.processInfo.systemUptime + Double(seconds)
        var batches: UInt64 = 0
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            if ProcessInfo.processInfo.thermalState == .critical { throw DiagnosticError.failed("Stopped: critical thermal state") }
            guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
                throw DiagnosticError.failed("Metal command failed")
            }
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(buffer, offset: 0, index: 0)
            encoder.dispatchThreads(MTLSize(width: 65_536, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: min(256, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
            encoder.endEncoding(); command.commit()
            // A submitted GPU command cannot be revoked; keep batches short and drain before returning.
            while command.status != .completed && command.status != .error {
                try? await Task.sleep(for: .milliseconds(10))
                if Task.isCancelled { command.waitUntilCompleted(); throw CancellationError() }
            }
            if let error = command.error { throw error }
            batches += 1
        }
        return batches
    }
}
