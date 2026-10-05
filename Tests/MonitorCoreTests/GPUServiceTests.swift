import Foundation
import Testing
@testable import MonitorCore

struct GPUServiceTests {
    @Test func dedicatedCapacityIsReportedByHardwareNotAFourGBProfile() {
        for gb: UInt64 in [1, 2, 4, 6, 8, 12, 16, 24, 32, 48, 64] {
            #expect(GPUService.totalVRAM(["VRAM,totalMB": NSNumber(value: gb * 1024)]) == gb * 1_073_741_824)
            #expect(GPUService.totalVRAM(["VRAM,totalsize": NSNumber(value: gb * 1_073_741_824)]) == gb * 1_073_741_824)
        }
    }
    @Test func registryDataIsDecodedWithoutAlignmentAssumptions() {
        #expect(GPUService.totalVRAM(["VRAM,totalMB": Data([0, 32, 0, 0])]) == UInt64(8) * 1_073_741_824)
        #expect(GPUService.totalVRAM(["VRAM,totalsize": Data([0, 0, 0, 0, 4, 0, 0, 0])]) == UInt64(16) * 1_073_741_824)
        #expect(GPUService.modelName(Data("AMD Radeon Pro 580\0ignored".utf8)) == "AMD Radeon Pro 580")
        #expect(GPUService.modelName("NVIDIA GeForce GTX 780M") == "NVIDIA GeForce GTX 780M")
        #expect(GPUService.modelName(Data([0xff, 0])) == nil)
    }
    @Test func unknownAndInvalidCapacityNeverBecomesFourGBOrAWorkingSet() {
        for values: [String: Any] in [[:], ["VRAM,totalMB": -1], ["VRAM,totalMB": true],
                                    ["VRAM,totalMB": Double.nan], ["VRAM,totalMB": 0.5],
                                    ["VRAM,totalMB": UInt64.max], ["recommendedMaxWorkingSetSize": 4_000_000_000],
                                    ["vramUsedBytes": 4_000_000_000, "vramFreeBytes": 1]] {
            #expect(GPUService.totalVRAM(values) == nil)
        }
        #expect(GPUService.unavailable.totalVRAM == nil)
        #expect(!GPUService.unavailable.name.contains("570"))
    }
    @Test func activeMemoryCanExceedFourGBOnLargerCards() {
        let gb: UInt64 = 1_073_741_824
        #expect(GPUService.activeVRAM(["inUseVidMemoryBytes": 7 * gb], total: 8 * gb) == 7 * gb)
        #expect(GPUService.activeVRAM(["inUseVidMemoryBytes": 15 * gb], total: 16 * gb) == 15 * gb)
        #expect(GPUService.activeVRAM(["inUseVidMemoryBytes": 7 * gb], total: 4 * gb) == nil)
        #expect(GPUService.activeVRAM(["vramUsedBytes": 8 * gb, "allocated_size": 8 * gb], total: 8 * gb) == nil)
    }
    @Test func physicalCapacityWinsOverAnAcceleratorBudget() {
        let values = GPUService.mergedProperties(accelerator: ["VRAM,totalsize": UInt64(4) * 1_073_741_824],
            device: ["VRAM,totalMB": 8192, "model": "Radeon Pro 580"])
        #expect(GPUService.totalVRAM(values) == UInt64(8) * 1_073_741_824)
        #expect(GPUService.modelName(values["model"]) == "Radeon Pro 580")
    }
    @Test func loadAndTemperatureRejectInvalidReadings() {
        #expect(GPUService.utilization(["Device Utilization %": 72]) == 72)
        #expect(GPUService.utilization(["GPU Activity(%)": 24]) == 24)
        #expect(GPUService.utilization(["Device Utilization %": 101]) == nil)
        #expect(GPUService.utilization(["Device Utilization %": true]) == nil)
        #expect(GPUService.utilization(["Device Utilization %": Double.infinity]) == nil)
        #expect(GPUService.temperature(["Temperature(C)": 58]) == 58)
        #expect(GPUService.temperature(["Temperature(C)": -7]) == nil)
    }
}
