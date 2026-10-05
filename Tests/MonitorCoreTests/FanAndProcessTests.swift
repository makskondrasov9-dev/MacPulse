import Darwin
import Foundation
import Testing
@testable import MonitorCore

struct FanAndProcessTests {
    @Test func fanFormatsRoundTripAndRejectInvalidValues() throws {
        for type in ["fpe2", "flt "] {
            let code = try SMCDecoder.fourCC(type)
            for rpm in [1200.0, 1550.0, 2700.0] {
                let bytes = try FanCodec.encodeRPM(rpm, type: code)
                #expect(try FanCodec.decode(FanValue(type: code, bytes: bytes)) == rpm)
            }
            #expect(throws: SMCError.self) { try FanCodec.encodeRPM(.nan, type: code) }
            #expect(throws: SMCError.self) { try FanCodec.encodeRPM(-100, type: code) }
        }
        #expect(try FanCodec.decode(FanValue(type: SMCDecoder.fourCC("ui8 "), bytes: [0])) == 0)
    }

    @Test func curvePreservesHardwareBoundsAndInterpolates() throws {
        var config = FanConfiguration(mode: .temperature, minimumRPM: 1200, maximumRPM: 2700,
                                      startTemperature: 50, fullTemperature: 80)
        #expect(try config.target(hardwareMinimum: 1200, hardwareMaximum: 2700, temperature: 30) == 1200)
        #expect(try config.target(hardwareMinimum: 1200, hardwareMaximum: 2700, temperature: 65) == 1950)
        #expect(try config.target(hardwareMinimum: 1200, hardwareMaximum: 2700, temperature: 100) == 2700)
        #expect(throws: FanError.self) { try config.target(hardwareMinimum: 1200, hardwareMaximum: 2700, temperature: nil) }
        config.minimumRPM = 0
        #expect(throws: FanError.self) { try config.target(hardwareMinimum: 1200, hardwareMaximum: 2700, temperature: 60) }
        config.minimumRPM = 1200; config.fullTemperature = 52
        #expect(throws: FanError.self) { try config.target(hardwareMinimum: 1200, hardwareMaximum: 2700, temperature: 60) }
    }

    @Test func expiredOrFutureLeaseIsRejected() {
        #expect(FanLease(configurations: [:]).isFresh)
        #expect(!FanLease(configurations: [:], updatedAt: Date().addingTimeInterval(-10)).isFresh)
        #expect(!FanLease(configurations: [:], updatedAt: Date().addingTimeInterval(60)).isFresh)
    }

    @Test func onlyDisposableChildIsTerminatedAndStaleIdentityIsRejected() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        var service = ProcessService()
        let process = try #require(service.sample().first { $0.pid == child.processIdentifier })
        var stale = process
        stale.startedSeconds += 1
        #expect(throws: ProcessControlError.self) { try ProcessControlService.terminate(stale) }
        #expect(child.isRunning)
        try ProcessControlService.terminate(process)
        for _ in 0..<20 where child.isRunning { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!child.isRunning)
        #expect(child.terminationReason == .uncaughtSignal)
    }

    @Test func criticalProcessesAreProtectedAndWarningsExplainConsequences() {
        let critical = ProcessMetrics(pid: 42, name: "WindowServer", cpu: nil, residentBytes: 0, startedSeconds: 1)
        #expect(!ProcessControlService.canTerminate(critical))
        #expect(throws: ProcessControlError.self) { try ProcessControlService.terminate(critical) }
        let finder = ProcessMetrics(pid: 43, name: "Finder", cpu: nil, residentBytes: 0, startedSeconds: 1)
        #expect(ProcessControlService.warning(for: finder).hasPrefix(
            L10n.template("Будут закрыты окна Finder; файловые операции могут прерваться. ")))
    }
}
