import CSystem
import Darwin
import Foundation

public enum FanMode: String, Codable, Sendable, CaseIterable { case automatic, minimum, temperature }
public enum FanSensor: String, Codable, Sendable, CaseIterable { case cpu, gpu }

public struct FanConfiguration: Codable, Sendable, Equatable {
    public var mode: FanMode
    public var minimumRPM: Double
    public var maximumRPM: Double
    public var startTemperature: Double
    public var fullTemperature: Double
    public var sensor: FanSensor
    public init(mode: FanMode = .automatic, minimumRPM: Double, maximumRPM: Double,
                startTemperature: Double = 50, fullTemperature: Double = 80, sensor: FanSensor = .cpu) {
        self.mode = mode; self.minimumRPM = minimumRPM; self.maximumRPM = maximumRPM
        self.startTemperature = startTemperature; self.fullTemperature = fullTemperature; self.sensor = sensor
    }

    public func target(hardwareMinimum: Double, hardwareMaximum: Double, temperature: Double?) throws -> Double {
        guard minimumRPM.isFinite, maximumRPM.isFinite, startTemperature.isFinite, fullTemperature.isFinite,
              hardwareMinimum > 0, hardwareMaximum > hardwareMinimum,
              minimumRPM >= hardwareMinimum, maximumRPM <= hardwareMaximum, maximumRPM >= minimumRPM,
              (30...85).contains(startTemperature), (40...95).contains(fullTemperature),
              fullTemperature >= startTemperature + 5 else {
            throw FanError.message("Проверьте диапазон оборотов и температур: границы должны отличаться минимум на 5 °C.")
        }
        switch mode {
        case .automatic: return hardwareMinimum
        case .minimum: return minimumRPM
        case .temperature:
            guard let temperature, temperature.isFinite, (10...150).contains(temperature) else {
                throw FanError.message("Датчик температуры недоступен. Возвращено штатное управление.")
            }
            let fraction = min(1, max(0, (temperature - startTemperature) / (fullTemperature - startTemperature)))
            return minimumRPM + (maximumRPM - minimumRPM) * fraction
        }
    }
}

public struct FanLease: Codable, Sendable {
    public let updatedAt: Date
    public let configurations: [Int: FanConfiguration]
    public let stop: Bool
    public init(configurations: [Int: FanConfiguration], stop: Bool = false, updatedAt: Date = Date()) {
        self.configurations = configurations; self.stop = stop; self.updatedAt = updatedAt
    }
    public var isFresh: Bool { abs(updatedAt.timeIntervalSinceNow) < 8 }
}

public struct FanWorkerStatus: Codable, Sendable {
    public let active: Bool
    public let restored: Bool
    public let message: String
    public let updatedAt: Date
}

/// An explicitly authorized session, not an installed daemon. Writes are restricted
/// to Intel fan minima. A stale UI heartbeat or dead/reused PID ends the session.
public enum FanControlWorker {
    public static func run(directory: String, parentPID: Int32, owner: UInt32, started: UInt64, micros: UInt64) throws {
        guard parentPID > 1, owner != 0, started > 0 else { throw FanError.message("Некорректная сессия вентилятора.") }
        let dir = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dir >= 0 else { throw FanError.message("Каталог сессии недоступен.") }
        defer { close(dir) }
        var info = stat()
        guard fstat(dir, &info) == 0, info.st_uid == owner, info.st_mode & 0o777 == 0o700 else {
            throw FanError.message("Недопустимые права каталога сессии.")
        }
        let statusFD = openat(dir, "status.json", O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
        guard statusFD >= 0 else { throw FanError.message("Файл статуса отсутствует.") }
        defer { close(statusFD) }
        guard fstat(statusFD, &info) == 0, info.st_uid == owner, info.st_nlink == 1,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_mode & 0o777 == 0o600 else {
            throw FanError.message("Недопустимый файл статуса.")
        }
        func publish(active: Bool, restored: Bool, message: String) {
            let status = FanWorkerStatus(active: active, restored: restored, message: message, updatedAt: Date())
            guard let data = try? JSONEncoder().encode(status) else { return }
            _ = ftruncate(statusFD, 0)
            data.withUnsafeBytes { buffer in _ = pwrite(statusFD, buffer.baseAddress, buffer.count, 0) }
        }
        func parentIsAlive() -> Bool {
            var task = proc_taskallinfo()
            let size = Int32(MemoryLayout<proc_taskallinfo>.size)
            return proc_pidinfo(parentPID, PROC_PIDTASKALLINFO, 0, &task, size) == size &&
                task.pbsd.pbi_uid == owner && task.pbsd.pbi_start_tvsec == started && task.pbsd.pbi_start_tvusec == micros
        }
        func readLease() throws -> FanLease {
            let fd = openat(dir, "lease.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw FanError.message("Сессия закрыта.") }
            defer { close(fd) }
            var file = stat()
            guard fstat(fd, &file) == 0, file.st_uid == owner, file.st_nlink == 1,
                  file.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), (1...65536).contains(file.st_size) else {
                throw FanError.message("Некорректные данные сессии.")
            }
            var buffer = [UInt8](repeating: 0, count: Int(file.st_size))
            let size = buffer.count
            guard read(fd, &buffer, size) == size else { throw FanError.message("Неполные данные сессии.") }
            return try JSONDecoder().decode(FanLease.self, from: Data(buffer))
        }
        // Only one authorized session may alter fan minima at a time.
        let lockFD = open("/var/run/MacPulse-fans.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else {
            publish(active: false, restored: true, message: "Не удалось получить доступ администратора для управления.")
            return
        }
        defer { close(lockFD) }
        var lockInfo = stat()
        guard fstat(lockFD, &lockInfo) == 0, lockInfo.st_uid == 0, lockInfo.st_nlink == 1,
              lockInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            publish(active: false, restored: true, message: "Уже работает другая сессия управления вентиляторами.")
            return
        }
        let device = FanDevice()
        let fans = device.snapshot().fans
        let original = Dictionary(uniqueKeysWithValues: fans.map { ($0.id, $0.minimum) })
        var lastWritten: [Int: Double] = [:]
        var touched: Set<Int> = []
        var message = "Штатное управление восстановлено."
        do {
            guard parentIsAlive(), !fans.isEmpty else { throw FanError.message("Сессия или датчики недоступны.") }
            while parentIsAlive() {
                let lease = try readLease()
                if lease.stop || !lease.isFresh { break }
                guard lease.configurations.keys.allSatisfy({ original[$0] != nil }) else { throw FanError.message("Вентилятор не найден.") }
                for fan in fans {
                    let setting = lease.configurations[fan.id]
                    if setting == nil || setting?.mode == .automatic {
                        if touched.contains(fan.id) {
                            try device.writeMinimum(id: fan.id, rpm: fan.minimum)
                            touched.remove(fan.id); lastWritten[fan.id] = nil
                        }
                        continue
                    }
                    guard fan.controllable, device.automaticMode(id: fan.id) else {
                        throw FanError.message("Управление недоступно или включено другой программой. Закройте другие утилиты вентиляторов.")
                    }
                    let actualMinimum = try device.speed("F\(fan.id)Mn")
                    guard abs(actualMinimum - (lastWritten[fan.id] ?? fan.minimum)) < 1 else {
                        // Do not overwrite a concurrent controller's setting.
                        touched.remove(fan.id)
                        throw FanError.message("Обороты изменены другой программой. Сессия остановлена.")
                    }
                    guard let setting else { continue }
                    var temperature: Double?
                    if setting.mode == .temperature {
                        let keys = setting.sensor == .cpu ? ["TC0P", "TC0D", "TC0E", "TC0F"] : ["TG0D", "TG0P"]
                        for key in keys {
                            if let raw = try? device.read(key), let value = try? SMCDecoder.temperature(type: raw.type, bytes: raw.bytes), value >= 10 {
                                temperature = value; break
                            }
                        }
                    }
                    let target = try setting.target(hardwareMinimum: fan.minimum, hardwareMaximum: fan.maximum, temperature: temperature)
                    if abs(actualMinimum - target) >= 1 {
                        // Include a potentially partially successful write in restoration.
                        touched.insert(fan.id)
                        try device.writeMinimum(id: fan.id, rpm: target)
                        lastWritten[fan.id] = target
                    }
                }
                publish(active: true, restored: false, message: "Настройки применены. Штатная автоматика может повысить обороты.")
                Thread.sleep(forTimeInterval: 1)
            }
        } catch { message = "\(error). Штатное управление восстановлено." }
        var failed: [Int] = []
        for id in touched.sorted() {
            var restored = false
            for _ in 0..<3 {
                do {
                    if abs(try device.speed("F\(id)Mn") - original[id]!) >= 1 {
                        try device.writeMinimum(id: id, rpm: original[id]!)
                    }
                    restored = true; break
                }
                catch { Thread.sleep(forTimeInterval: 0.2) }
            }
            if !restored { failed.append(id) }
        }
        if !failed.isEmpty {
            message = "Не удалось восстановить минимум вентиляторов \(failed). Перезагрузите Mac для возврата штатных настроек."
        }
        publish(active: false, restored: failed.isEmpty, message: message)
    }
}
