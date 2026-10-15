import Foundation

public struct ProcessConnection: Identifiable, Sendable, Equatable {
    public let pid: Int32
    public let process: String
    public let descriptor: String
    public let transport: String
    public let local: String
    public let remote: String?
    public let state: String
    public var id: String { "\(pid):\(descriptor):\(transport):\(local):\(remote ?? "")" }
    public var isActiveRemote: Bool { remote != nil && (transport == "UDP" || state == "ESTABLISHED") }
    public func matches(_ query: String) -> Bool {
        query.isEmpty || [process, String(pid), local, remote ?? "", transport, state].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// Parses lsof's field format, not its aligned human-readable table. Never resolves DNS.
public enum ConnectionParser {
    public static func parse(_ data: Data) -> [ProcessConnection] {
        var result: [ProcessConnection] = [], seen = Set<String>()
        var pid: Int32?, name = "", descriptor: String?, transport = "", endpoint = "", state = ""
        func flush() {
            guard let pid, pid > 0, let descriptor, ["TCP", "UDP"].contains(transport), !endpoint.isEmpty else { return }
            let endpoints = endpoint.components(separatedBy: "->")
            guard endpoints.count <= 2 else { return }
            let row = ProcessConnection(pid: pid, process: name, descriptor: descriptor, transport: transport,
                local: endpoints[0], remote: endpoints.count == 2 ? endpoints[1] : nil,
                state: state.isEmpty ? (transport == "UDP" ? "UDP" : "UNKNOWN") : state)
            if seen.insert(row.id).inserted { result.append(row) }
        }
        // Newlines separate process/file sets even with -F0. NUL terminates fields.
        for field in String(decoding: data, as: UTF8.self).split(whereSeparator: { $0 == "\0" || $0 == "\n" || $0 == "\r" }) {
            guard let kind = field.first else { continue }
            let value = String(field.dropFirst())
            switch kind {
            case "p": flush(); pid = Int32(value); name = ""; descriptor = nil; transport = ""; endpoint = ""; state = ""
            case "c": name = value
            case "f": flush(); descriptor = value; transport = ""; endpoint = ""; state = ""
            case "P": transport = value
            case "n": endpoint = value
            case "T": if value.hasPrefix("ST=") { state = String(value.dropFirst(3)) }
            default: break
            }
        }
        flush()
        return result
    }
}

public actor NetworkProcessMonitorService {
    public init() {}
    public func sample() async throws -> [ProcessConnection] {
        let output = try await DiagnosticProcess.run("/usr/sbin/lsof", arguments: ["-n", "-P", "-iTCP", "-iUDP", "-F0pcfPnT"], timeout: 5, maximumBytes: 2_000_000)
        try Task.checkCancellation()
        let rows = ConnectionParser.parse(output.data)
        // lsof returns 1 when no matching sockets are visible to this user.
        guard output.status == 0 || (output.status == 1 && output.data.isEmpty) else {
            throw DiagnosticError.failed("Unable to read process connections")
        }
        return rows
    }
}
