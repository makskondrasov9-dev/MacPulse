import CSystem
import Darwin
import Foundation

struct MemoryService {
    func sample() -> MemoryMetrics? {
        let host = mach_host_self()
        defer { mach_port_deallocate(MonitorTaskSelf(), host) }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let page = UInt64(pageSize)
        return MemoryMetrics(total: ProcessInfo.processInfo.physicalMemory,
                             wired: UInt64(stats.wire_count) * page,
                             active: UInt64(stats.active_count) * page,
                             compressed: UInt64(stats.compressor_page_count) * page,
                             freeAndInactive: (UInt64(stats.free_count) + UInt64(stats.inactive_count)) * page)
    }
}
