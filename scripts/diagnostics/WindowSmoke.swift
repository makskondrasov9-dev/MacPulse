import AppKit
import SwiftUI
import MonitorCore

@main
struct StageOneSmoke: App {
    @StateObject private var model = MonitorModel()
    @State private var started = false
    var body: some Scene {
        Window("MacPulse Stage 1 Smoke", id: "dashboard") {
            MainWindowView(model: model, fanModel: model.fans)
                .task {
                    guard !started else { return }; started = true
                    let delegate = AppDelegate()
                    delegate.applyMode("regular")
                    precondition(NSApp.activationPolicy() == .regular)
                    model.start()
                    try? await Task.sleep(for: .seconds(4))
                    guard let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.frame.width > 500 }) else { exit(2) }
                    window.setContentSize(NSSize(width: 1040, height: 650))
                    window.makeKeyAndOrderFront(nil)
                    try? await Task.sleep(for: .seconds(1))
                    precondition(window.level == .normal)
                    @MainActor func scrolls(_ view: NSView) -> [NSScrollView] {
                        if let scroll = view as? NSScrollView { return [scroll] }
                        var result: [NSScrollView] = []
                        for child in view.subviews { result.append(contentsOf: scrolls(child)) }
                        return result
                    }
                    guard let scroll = scrolls(window.contentView!).first(where: { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 150 }) else { exit(3) }
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: 250))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    let before = scroll.contentView.bounds.origin.y
                    let previous = UserDefaults.standard.object(forKey: "hideUnavailableMetrics")
                    UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "hideUnavailableMetrics"), forKey: "hideUnavailableMetrics")
                    try? await Task.sleep(for: .seconds(1))
                    let after = scroll.contentView.bounds.origin.y
                    UserDefaults.standard.set(previous, forKey: "hideUnavailableMetrics")
                    print("Scroll before=\(before), after=\(after)")
                    precondition(before > 0 && abs(after - before) < 2, "Scroll jumped when toggling missing values")
                    delegate.applyMode("accessory")
                    precondition(NSApp.activationPolicy() == .accessory)
                    delegate.applyMode("regular")
                    precondition(NSApp.activationPolicy() == .regular)
                    precondition(window.level == .normal)
                    print("PASS: regular/accessory/regular activation, normal window level, stable scroll")
                    await model.stop()
                    exit(0)
                }
        }.defaultSize(width: 1040, height: 650)
    }
}
