import CSystem
import Darwin
import Foundation

public enum ProcessControlError: Error, LocalizedError {
    case changed, protected, permission, failed(Int32)
    public var errorDescription: String? {
        switch self {
        case .changed: "Процесс уже завершён или PID принадлежит другому процессу. Обновите список."
        case .protected: "Этот процесс необходим для работы системы или самого MacPulse. Его завершение заблокировано."
        case .permission: "macOS не разрешила завершить этот процесс. MacPulse не повышает права для завершения системных служб."
        case .failed(let code): "Не удалось отправить запрос завершения (код \(code))."
        }
    }
}

public enum ProcessControlService {
    public static func currentProcess() -> ProcessMetrics? {
        var service = ProcessService()
        return service.sample().first { $0.pid == getpid() }
    }

    public static func warning(for process: ProcessMetrics) -> String {
        let base = L("Несохранённые изменения могут быть потеряны. Процесс может завершиться не сразу или быть перезапущен системой.")
        switch process.name.lowercased() {
        case "finder": return L("Будут закрыты окна Finder; файловые операции могут прерваться. ") + base
        case "dock": return L("Панель Dock и переключение рабочих столов временно станут недоступны. ") + base
        case "systemuiserver", "controlcenter": return L("Элементы строки меню и Центр управления временно исчезнут. ") + base
        case "coreaudiod": return L("Звук и запись аудио могут прерваться. ") + base
        case "mds", "mdworker", "mdworker_shared": return L("Индексация Spotlight и поиск файлов могут временно остановиться. ") + base
        default:
            return process.isSystem ? L("Это системная служба. Связанные функции macOS могут перестать работать до перезапуска службы или входа в систему. ") + base : base
        }
    }

    public static func description(for process: ProcessMetrics) -> String {
        switch process.name.lowercased() {
        case "finder": "Finder — управление файлами, папками и рабочим столом."
        case "dock": "Dock — панель приложений и переключение рабочих столов."
        case "windowserver": "WindowServer — отображение окон и графического интерфейса macOS."
        case "kernel_task": "Ядро macOS — управление оборудованием и системными ресурсами."
        case "launchd": "launchd — запуск и управление системными службами."
        case "loginwindow": "loginwindow — вход в систему и пользовательская сессия."
        case "coreaudiod": "Системная служба воспроизведения и записи звука."
        case "systemuiserver", "controlcenter": "Системная служба строки меню и Центра управления."
        case "mds", "mdworker", "mdworker_shared": "Spotlight — индексирование и поиск файлов."
        case "imacmonitor", "macpulse", "macpulsefanhelper": "Компонент MacPulse — мониторинг и управление вентиляторами."
        default: process.isSystem ? "Системный процесс macOS. Подробное назначение не определено."
            : "Процесс приложения или фоновая служба. Проверьте путь к исполняемому файлу, чтобы определить владельца."
        }
    }

    public static func canTerminate(_ process: ProcessMetrics) -> Bool {
        process.pid > 1 && process.pid != getpid() && process.startedSeconds > 0 &&
        !["kernel_task", "launchd", "windowserver", "loginwindow", "watchdogd", "macpulsefanhelper"].contains(process.name.lowercased())
    }

    /// Revalidate identity immediately before SIGTERM; never signal a process group or escalate to SIGKILL.
    public static func terminate(_ process: ProcessMetrics) throws {
        guard canTerminate(process) else { throw ProcessControlError.protected }
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.size)
        guard proc_pidinfo(process.pid, PROC_PIDTASKALLINFO, 0, &info, size) == size,
              info.pbsd.pbi_start_tvsec == process.startedSeconds,
              info.pbsd.pbi_start_tvusec == process.startedMicroseconds,
              info.pbsd.pbi_uid == process.ownerUID else { throw ProcessControlError.changed }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let capacity = UInt32(path.count)
        guard proc_pidpath(process.pid, &path, capacity) > 0 else { throw ProcessControlError.changed }
        let currentPath = String(decoding: path.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard !process.executablePath.isEmpty, currentPath == process.executablePath else { throw ProcessControlError.changed }
        guard kill(process.pid, SIGTERM) == 0 else {
            if errno == ESRCH { throw ProcessControlError.changed }
            if errno == EPERM { throw ProcessControlError.permission }
            throw ProcessControlError.failed(errno)
        }
    }
}
