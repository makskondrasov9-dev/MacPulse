import AppKit
import SwiftUI
import MonitorCore

@main struct FlagshipSmoke: App {
    @StateObject var model = MonitorModel()
    @State var started = false
    var body: some Scene {
        Window("MacPulse 1.0 smoke", id: "smoke") {
            NetworkProcessesView().frame(minWidth: 1000, minHeight: 600)
                .task {
                    guard !started else { return }; started = true
                    NSApp.setActivationPolicy(.regular)
                    let defaults = UserDefaults.standard
                    let keys = ["desktopWidgetsEnabled", "desktopWidgetsFloating", "desktopWidgetsClickThrough", "desktopWidgetsOpacity"]
                    let original = keys.map { defaults.object(forKey: $0) }
                    model.start()
                    defaults.set(true, forKey: keys[0]); defaults.set(true, forKey: keys[1]); defaults.set(false, forKey: keys[2]); defaults.set(0.6, forKey: keys[3])
                    DesktopWidgetService.shared.sync(model)
                    try? await Task.sleep(for: .seconds(4))
                    let panels = NSApp.windows.compactMap { $0 as? NSPanel }.filter { $0.frameAutosaveName.hasPrefix("MacPulse.HUD.") }
                    precondition(panels.count == 3)
                    precondition(panels.allSatisfy { $0.level == .floating && abs($0.alphaValue - 0.6) < 0.01 && $0.isMovableByWindowBackground })
                    let panel = panels[0], name = panel.frameAutosaveName
                    panel.setFrameOrigin(NSPoint(x: 200, y: 250)); let origin = panel.frame.origin
                    capture(panel, "flagship-widget")
                    defaults.set(false, forKey: keys[0]); DesktopWidgetService.shared.sync(model)
                    defaults.set(true, forKey: keys[0]); defaults.set(false, forKey: keys[1]); defaults.set(true, forKey: keys[2]); DesktopWidgetService.shared.sync(model)
                    let restored = NSApp.windows.first { $0.frameAutosaveName == name && $0.isVisible }!
                    precondition(restored.frame.origin == origin)
                    precondition(restored.ignoresMouseEvents)
                    precondition(restored.level.rawValue == Int(CGWindowLevelForKey(.desktopWindow)) + 1)
                    do {
                        let connections = try await NetworkProcessMonitorService().sample()
                        print("Live TCP/UDP rows: \(connections.count)")
                    } catch { print("Live sockets FAILED: \(error)") }
                    if let window = NSApp.windows.first(where: { $0.title == "MacPulse 1.0 smoke" }) { capture(window, "flagship-network") }
                    await model.stop()
                    for (index, key) in keys.enumerated() { if let value = original[index] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
                    print("HUD: 3 panels, floating/desktop level, opacity, click-through and saved coordinates verified")
                    exit(0)
                }
        }
    }
    @MainActor func capture(_ window: NSWindow, _ name: String) {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: ".build/\(name).png"))
    }
}
