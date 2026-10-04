import Foundation
import MonitorCore

@main
struct FanHelperMain {
    static func main() async {
        let args = CommandLine.arguments
        if args.count == 7, args[1] == "--session", let pid = Int32(args[3]), let uid = UInt32(args[4]),
           let seconds = UInt64(args[5]), let micros = UInt64(args[6]) {
            do { try FanControlWorker.run(directory: args[2], parentPID: pid, owner: uid, started: seconds, micros: micros) }
            catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
        } else if args.count == 1 || args == [args[0], "--probe"] {
            let snapshot = await FanService().sample()
            if let data = try? JSONEncoder().encode(snapshot) { print(String(decoding: data, as: UTF8.self)) }
        } else { exit(2) }
    }
}
