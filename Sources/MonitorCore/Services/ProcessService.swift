import CSystem
import Darwin
import Foundation

struct ProcessService {
    private struct Previous {
        let ticks: UInt64
        let time: TimeInterval
        let startedSeconds: UInt64
        let startedMicroseconds: UInt64
    }
    private var previous: [Int32: Previous] = [:]

    mutating func sample() -> [ProcessMetrics] {
        let required = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard required > 0 else { previous.removeAll(); return [] }
        var pids = [Int32](repeating: 0, count: Int(required) / MemoryLayout<Int32>.size + 256)
        let capacity = Int32(pids.count * MemoryLayout<Int32>.size)
        let actual = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, capacity) }
        guard actual > 0 else { previous.removeAll(); return [] }
        var next: [Int32: Previous] = [:]
        var result: [ProcessMetrics] = []
        for pid in pids.prefix(min(pids.count, Int(actual) / MemoryLayout<Int32>.size)) where pid > 0 {
            var info = proc_taskallinfo()
            let size = Int32(MemoryLayout<proc_taskallinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, size) == size else { continue }
            let ticks = info.ptinfo.pti_total_user &+ info.ptinfo.pti_total_system
            let now = ProcessInfo.processInfo.systemUptime
            let seconds = info.pbsd.pbi_start_tvsec
            let micros = info.pbsd.pbi_start_tvusec
            var cpu: Double?
            if let old = previous[pid], old.startedSeconds == seconds, old.startedMicroseconds == micros,
               ticks >= old.ticks, now > old.time {
                cpu = Double(ticks - old.ticks) / 1_000_000_000 / (now - old.time) * 100
            }
            next[pid] = Previous(ticks: ticks, time: now, startedSeconds: seconds, startedMicroseconds: micros)
            let name = withUnsafeBytes(of: &info.pbsd.pbi_name) {
                String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let pathSize = UInt32(path.count)
            let pathCount = proc_pidpath(pid, &path, pathSize)
            let executable = pathCount > 0 ? String(decoding: path.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
            result.append(ProcessMetrics(pid: pid, name: name.isEmpty ? "PID \(pid)" : name,
                                         cpu: cpu, residentBytes: info.ptinfo.pti_resident_size,
                                         startedSeconds: seconds, startedMicroseconds: micros,
                                         ownerUID: info.pbsd.pbi_uid, executablePath: executable))
        }
        previous = next
        return result
    }
}
