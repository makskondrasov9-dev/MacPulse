import AppKit
import SwiftUI
import MonitorCore

/// A separate executable: real views and read-only live metrics, isolated preferences.
@main struct CaptureApp: App {
    @StateObject private var model = MonitorModel()
    @State private var started = false
    init() {
        UserDefaults.standard.register(defaults: ["appLanguage": "en", "appearance": "dark", "menuBarTextStyle": "chartAndText", "showCPUChart": true, "showNetworkChart": true])
    }
    var body: some Scene {
        WindowGroup("MacPulse") {
            MainWindowView(model: model, fanModel: model.fans)
                .environment(\.locale, Locale(identifier: "en"))
                .preferredColorScheme(.dark)
                .task {
                    guard !started else { return }; started = true
                    NSApp.setActivationPolicy(.regular)
                    NSApp.appearance = NSAppearance(named: .darkAqua)
                    model.start()
                    model.uninstaller.refresh()
                    try? await Task.sleep(for: .seconds(26))
                    guard let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.frame.width > 500 }) else { exit(1) }
                    window.setContentSize(NSSize(width: 1180, height: 840))
                    window.center()
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    for (section, filename) in [("Монитор", "dashboard"), ("Очистка", "cleaner"), ("Деинсталлятор", "uninstaller"), ("Вентиляторы", "fans")] {
                        NotificationCenter.default.post(name: .init("MacPulseScreenshotSection"), object: section)
                        try? await Task.sleep(for: .seconds(1))
                        window.setContentSize(NSSize(width: 1180, height: 900))
                        window.center()
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                        try? await Task.sleep(for: .seconds(2))
                        capture(windowID: window.windowNumber, name: filename)
                    }
                    if let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
                       let item = windows.first(where: { info in
                           guard (info[kCGWindowOwnerPID as String] as? Int) == Int(ProcessInfo.processInfo.processIdentifier),
                                 let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
                           return (bounds["Height"] ?? 0) <= 40 && (bounds["Width"] ?? 0) > 30
                       }), let id = item[kCGWindowNumber as String] as? Int {
                        if let bounds = item[kCGWindowBounds as String] as? [String: CGFloat] {
                            let region = ["X", "Y", "Width", "Height"].map { String(Int(bounds[$0] ?? 0)) }.joined(separator: ",")
                            capture(windowID: id, name: "menubar", region: region)
                        }
                    } else { print("No visible menu bar item found"); await model.stop(); exit(2) }
                    await model.stop()
                    exit(0)
                }
        }.defaultSize(width: 1180, height: 840)
        MenuBarExtra { MenuBarView(model: model) } label: { MenuBarLabel(model: model) }
            .menuBarExtraStyle(.window)
    }
    @MainActor private func capture(windowID: Int, name: String, region: String? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", region.map { "-R\($0)" } ?? "-l\(windowID)", "docs/screenshots/\(name).png"]
        do { try process.run(); process.waitUntilExit() }
        catch { print("Screenshot failed:", error); exit(1) }
        if process.terminationStatus != 0 {
            // The command-line tool may lack Screen Recording permission even when
            // this process can capture its own window. Never capture other apps.
            guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow,
                    CGWindowID(windowID), [.boundsIgnoreFraming, .bestResolution]),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
            do { try png.write(to: URL(fileURLWithPath: "docs/screenshots/\(name).png")) }
            catch { print("Cannot save screenshot:", error); exit(1) }
        }
        print("Captured", name)
    }
}
