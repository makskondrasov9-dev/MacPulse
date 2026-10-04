import Darwin
import Foundation
import Testing
@testable import MonitorCore

struct FanHardwareTests {
    /// Explicit opt-in: briefly raises the existing minimum, never lowers it,
    /// then exercises the independent heartbeat watchdog and verifies restoration.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACPULSE_FAN_CONTROL_TEST"] == "1"))
    func liveControlAndWatchdog() async throws {
        let identity = try #require(ProcessControlService.currentProcess())
        let service = FanService()
        let before = await service.sample()
        let fan = try #require(before.fans.first { $0.controllable })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-fan-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let statusURL = root.appendingPathComponent("status.json")
        #expect(FileManager.default.createFile(atPath: statusURL.path, contents: Data(), attributes: [.posixPermissions: 0o600]))
        let leaseURL = root.appendingPathComponent("lease.json")
        let target = min(fan.maximum, fan.minimum + 150)
        let setting = FanConfiguration(mode: .minimum, minimumRPM: target, maximumRPM: fan.maximum)
        func heartbeat() throws { try JSONEncoder().encode(FanLease(configurations: [fan.id: setting])).write(to: leaseURL, options: .atomic) }
        func status() -> FanWorkerStatus? {
            (try? Data(contentsOf: statusURL)).flatMap { try? JSONDecoder().decode(FanWorkerStatus.self, from: $0) }
        }
        try heartbeat()
        let helper = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/MacPulseFanHelper").resolvingSymlinksInPath()
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = [helper.path, "--session", root.path, String(identity.pid), String(identity.ownerUID),
                       String(identity.startedSeconds), String(identity.startedMicroseconds)].map(quote).joined(separator: " ")
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        child.arguments = ["-e", "do shell script \"\(literal)\" with administrator privileges"]
        child.standardOutput = FileHandle.nullDevice
        try child.run()
        defer {
            // A failing assertion must also leave an explicit restore request.
            if let data = try? JSONEncoder().encode(FanLease(configurations: [:], stop: true)) { try? data.write(to: leaseURL, options: .atomic) }
        }
        var active = false
        for _ in 0..<120 {
            try heartbeat()
            if status()?.active == true { active = true; break }
            if !child.isRunning { break }
            try await Task.sleep(for: .seconds(1))
        }
        #expect(active, "Fan helper did not activate: \(status()?.message ?? "authorization cancelled")")
        if active {
            let running = await service.sample()
            #expect(running.fans.first?.minimum == target)
            print("Fan test: original \(fan.minimum), requested \(target), measured minimum \(running.fans.first?.minimum ?? -1), RPM \(running.fans.first?.rpm ?? -1)")
            // Normal automatic switch restores the original minimum while the session lives.
            try JSONEncoder().encode(FanLease(configurations: [:])).write(to: leaseURL, options: .atomic)
            try await Task.sleep(for: .seconds(2))
            #expect(await service.sample().fans.first?.minimum == fan.minimum)
            print("Fan automatic switch restored minimum: \(fan.minimum)")
            // CPU curve saturates at the SAME bounded test ceiling (original + 150 RPM).
            let curve = FanConfiguration(mode: .temperature, minimumRPM: fan.minimum, maximumRPM: target,
                                         startTemperature: 30, fullTemperature: 40)
            try JSONEncoder().encode(FanLease(configurations: [fan.id: curve])).write(to: leaseURL, options: .atomic)
            try await Task.sleep(for: .seconds(2))
            #expect(await service.sample().fans.first?.minimum == target)
            print("Fan CPU temperature curve applied ceiling: \(target)")
            // No more heartbeat: simulate a frozen/crashed UI.
            for _ in 0..<15 where child.isRunning { try await Task.sleep(for: .seconds(1)) }
        }
        #expect(!child.isRunning)
        let report = try #require(status())
        #expect(report.restored && !report.active)
        let after = await service.sample()
        #expect(after.fans.first?.minimum == fan.minimum)
        print("Fan watchdog restored minimum: \(after.fans.first?.minimum ?? -1). \(report.message)")
        if !child.isRunning { try? FileManager.default.removeItem(at: root) }
    }
}
