import AppKit
import SwiftUI
import MonitorCore
import Darwin

@main struct OptimizationSmoke: App {
    @StateObject var model = MonitorModel()
    @State var started = false
    var body: some Scene {
        MenuBarExtra { Text("MacPulse optimization check") } label: { OptimizationLauncher(model: model) }
        Window("MacPulse optimization check", id: "dashboard") {
            MainWindowView(model: model, fanModel: model.fans).task {
                guard !started else { return }; started = true
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                let d = UserDefaults.standard
                var keys = ["desktopWidgetsEnabled", "desktopWidgetsFloating", "desktopWidgetsClickThrough", "desktopWidgetsOpacity", "widgetSize.compute", "widgetLocked.compute", "menuBarColorMode", "showCPUPercentage", "showRAMPercentage", "showGPUPercentage", "showCPUTemperature", "showNetworkSpeed", "showMenuBarIP", "showMenuBarVPN", "menuBarTextStyle", "showCPUChart", "showNetworkChart", "hideUnavailableMetrics"]
                for kind in DesktopWidgetKind.allCases {
                    for key in ["widgetEnabled.", "widgetSize.", "widgetLocked."] {
                        let value = key + kind.rawValue
                        if !keys.contains(value) { keys.append(value) }
                    }
                }
                let old = keys.map { d.object(forKey: $0) }
                for kind in DesktopWidgetKind.allCases { d.removeObject(forKey: "widgetEnabled." + kind.rawValue) }
                d.set(true, forKey: "showCPUPercentage"); d.set("category", forKey: "menuBarColorMode")
                for key in ["showRAMPercentage", "showGPUPercentage", "showCPUTemperature", "showNetworkSpeed", "showMenuBarIP", "showMenuBarVPN"] { d.set(false, forKey: key) }
                d.set("chartAndText", forKey: "menuBarTextStyle")
                d.set(true, forKey: "showCPUChart"); d.set(false, forKey: "showNetworkChart")
                model.fans.interfaceVisible = true; model.start()
                try? await Task.sleep(for: .seconds(5))
                guard let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) && $0.frame.width > 500 }) else { exit(2) }
                window.setContentSize(NSSize(width: 1040, height: 650)); window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .seconds(1))
                @MainActor func scrollIn(_ view: NSView) -> NSScrollView? {
                    if let scroll = view as? NSScrollView, (scroll.documentView?.frame.height ?? 0) > scroll.contentView.bounds.height + 200 { return scroll }
                    for child in view.subviews { if let found = scrollIn(child) { return found } }; return nil
                }
                guard let scroll = scrollIn(window.contentView!) else { exit(3) }
                NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: 250)); scroll.reflectScrolledClipView(scroll.contentView)
                NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
                d.set(!d.bool(forKey: "hideUnavailableMetrics"), forKey: "hideUnavailableMetrics")
                try? await Task.sleep(for: .seconds(1))
                print("Scroll offset after hiding: \(scroll.contentView.bounds.origin.y)"); fflush(nil)
                precondition(abs(scroll.contentView.bounds.origin.y - 250) < 2)
                // Exercise real height collapse, not merely a preference change with all sensors present.
                if let complete = model.dashboard.snapshot {
                    model.fullInterfaceVisible = false
                    let collector = MetricCollector()
                    let unavailable = await collector.sample(selection: .gpu)
                    await collector.close()
                    model.dashboard.accept(snapshot: unavailable, history: model.history)
                    d.set(false, forKey: "hideUnavailableMetrics")
                    try? await Task.sleep(for: .milliseconds(400))
                    let fullHeight = scroll.documentView!.frame.height
                    NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: 250))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
                    d.set(true, forKey: "hideUnavailableMetrics")
                    try? await Task.sleep(for: .milliseconds(400))
                    let collapsedHeight = scroll.documentView!.frame.height
                    precondition(fullHeight > collapsedHeight + 100)
                    precondition(abs(scroll.contentView.bounds.origin.y - 250) < 2)
                    print("Unavailable cards collapsed: document \(fullHeight) -> \(collapsedHeight); scroll offset retained at 250 pt"); fflush(nil)
                    model.dashboard.accept(snapshot: complete, history: model.history)
                    model.fullInterfaceVisible = true
                    try? await Task.sleep(for: .milliseconds(400))
                }
                NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
                let paused = Mirror(reflecting: model.dashboard).children.first { $0.label == "scrolling" }?.value as? Bool
                precondition(paused == true, "Native scroll observer was not attached to the dashboard")
                var frameIntervals: [Double] = []
                var lastFrame = ProcessInfo.processInfo.systemUptime
                for step in 0..<120 {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: 250 + Double(step % 60)))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    try? await Task.sleep(for: .milliseconds(16))
                    let current = ProcessInfo.processInfo.systemUptime
                    frameIntervals.append(current - lastFrame); lastFrame = current
                }
                NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
                let ordered = frameIntervals.sorted()
                print(String(format: "Scroll scheduling p95 %.1f ms, max %.1f ms", ordered[Int(Double(ordered.count - 1) * 0.95)] * 1000, ordered.last! * 1000)); fflush(nil)
                // Navigate through the actual sidebar; keep the SwiftUI scene hosting controller intact.
                // Non-gesture keyboard/accessibility scrolling must remain possible, too.
                let keyboardOffset = scroll.contentView.bounds.origin.y + 25
                scroll.contentView.scroll(to: NSPoint(x: 0, y: keyboardOffset))
                scroll.reflectScrolledClipView(scroll.contentView)
                try? await Task.sleep(for: .milliseconds(150))
                precondition(abs(scroll.contentView.bounds.origin.y - keyboardOffset) < 2)
                let savedOffset = scroll.contentView.bounds.origin.y
                print("Saved model scroll offset before navigation: \(model.dashboard.scrollOffset)"); fflush(nil)
                @MainActor func sidebarIn(_ view: NSView) -> NSTableView? {
                    if let table = view as? NSTableView, table.numberOfRows >= 6, table.bounds.width < 400 { return table }
                    for child in view.subviews { if let found = sidebarIn(child) { return found } }; return nil
                }
                guard let sidebar = sidebarIn(window.contentView!) else { fatalError("Native sidebar missing") }
                sidebar.selectRowIndexes(IndexSet(integer: model.fans.fans.isEmpty ? 3 : 4), byExtendingSelection: false)
                try? await Task.sleep(for: .milliseconds(600))
                @MainActor func tabIn(_ view: NSView) -> NSTabView? {
                    if let tabs = view as? NSTabView { return tabs }
                    for child in view.subviews { if let found = tabIn(child) { return found } }; return nil
                }
                guard let tabs = tabIn(window.contentView!) else { fatalError("Settings TabView missing") }
                precondition(tabs.numberOfTabViewItems == 4)
                for index in 0..<4 {
                    tabs.selectTabViewItem(at: index)
                    try? await Task.sleep(for: .milliseconds(300))
                    capture(window, "settings-tab-" + String(index))
                }
                sidebar.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
                try? await Task.sleep(for: .milliseconds(600))
                guard let restoredScroll = scrollIn(window.contentView!) else { fatalError("Dashboard missing") }
                print("Saved model offset after navigation: \(model.dashboard.scrollOffset)"); fflush(nil)
                print("Scroll offset after Settings navigation: \(restoredScroll.contentView.bounds.origin.y)"); fflush(nil)
                precondition(abs(restoredScroll.contentView.bounds.origin.y - savedOffset) < 2)
                var text = AttributedString("CPU 66% | RAM 44% | VRAM 61%")
                text.foregroundColor = .purple
                let chart = StatusLabelComposition(label: AttributedString(), cpu: [10,40,70,66], network: [0,50,30,100], icon: true, cpuColor: .cyan)
                let combined = StatusLabelComposition(label: text, cpu: [10,40,70,66], network: [0,50,30,100], icon: true, cpuColor: .cyan)
                for scheme in [ColorScheme.light, .dark] {
                    guard let chartImage = chart.image(scheme: scheme), let fullImage = combined.image(scheme: scheme),
                          let data = fullImage.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { fatalError("Menu image missing") }
                    precondition(!fullImage.isTemplate && fullImage.size.width > chartImage.size.width + 150)
                    var coloredTextPixels = 0
                    for x in (bitmap.pixelsWide / 2)..<bitmap.pixelsWide {
                        for y in 0..<bitmap.pixelsHigh {
                            if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.1,
                               abs(c.redComponent - c.greenComponent) > 0.1 { coloredTextPixels += 1 }
                        }
                    }
                    precondition(coloredTextPixels > 100, "Colored text lost in status image")
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".build/menu-combined-\(scheme).png"))
                    print("Combined status image: \(fullImage.size), colored text pixels \(coloredTextPixels)")
                }
                // Exercise the actual shared palette-to-SwiftUI rendering for both chart regions.
                for mode in ["mono", "accent", "category", "load"] {
                    let cpuColor = MenuChartPolicy.color(mode: mode, network: false, load: 60).viewColor(accent: .purple)
                    let networkColor = MenuChartPolicy.color(mode: mode, network: true, load: 90).viewColor(accent: .purple)
                    let view = StatusLabelComposition(label: AttributedString(), cpu: [10,90,20,80], network: [10,90,20,80], icon: false, cpuColor: cpuColor, networkColor: networkColor)
                    guard let data = view.image(scheme: .dark)?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { fatalError("Chart palette rendering failed") }
                    var left: [NSColor] = [], right: [NSColor] = []
                    for x in 0..<bitmap.pixelsWide {
                        for y in 0..<bitmap.pixelsHigh {
                            if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5 {
                                if x < 44 { left.append(color) }
                                if x >= 56 { right.append(color) }
                            }
                        }
                    }
                    precondition(!left.isEmpty && !right.isEmpty)
                    if mode == "mono" {
                        precondition((left + right).allSatisfy { abs($0.redComponent - $0.greenComponent) < 0.05 && abs($0.greenComponent - $0.blueComponent) < 0.05 })
                    } else if mode == "accent" {
                        precondition((left + right).allSatisfy { $0.blueComponent > $0.greenComponent && $0.redComponent > $0.greenComponent })
                    } else if mode == "category" {
                        precondition(right.allSatisfy { $0.greenComponent > $0.redComponent })
                    } else {
                        precondition(right.allSatisfy { $0.redComponent > $0.greenComponent })
                    }
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".build/menu-palette-" + mode + ".png"))
                }
                print("PASS: both rendered chart regions follow all four menu palette modes"); fflush(nil)
                capture(window, "optimization-dashboard")
                window.orderOut(nil)
                model.fullInterfaceVisible = false
                precondition(model.effectivePollingInterval == 3)
                d.set(true, forKey: "desktopWidgetsEnabled"); d.set(false, forKey: "desktopWidgetsFloating"); d.set(false, forKey: "desktopWidgetsClickThrough"); d.set(false, forKey: "widgetLocked.compute")
                DesktopWidgetService.shared.sync(model)
                precondition(model.effectivePollingInterval == model.pollingInterval)
                try? await Task.sleep(for: .seconds(3))
                guard let panel = NSApp.windows.first(where: { $0.frameAutosaveName == "MacPulse.HUD.compute" && $0.isVisible }) as? NSPanel else { exit(4) }
                precondition(!panel.ignoresMouseEvents && panel.isMovableByWindowBackground)
                precondition(panel.contentView!.acceptsFirstMouse(for: nil))
                precondition(panel.contentView!.hitTest(NSPoint(x: 80, y: 80)) === panel.contentView)
                precondition(panel.level.rawValue > Int(CGWindowLevelForKey(.desktopIconWindow)))
                guard let menu = panel.contentView?.perform(NSSelectorFromString("makeContextMenu"))?.takeUnretainedValue() as? NSMenu,
                      let sizes = menu.items.last?.submenu else { fatalError("Widget context menu missing") }
                menu.update(); sizes.update()
                precondition(!menu.autoenablesItems && !sizes.autoenablesItems)
                precondition(menu.items.allSatisfy(\.isEnabled) && sizes.items.allSatisfy(\.isEnabled))
                for item in sizes.items {
                    let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
                    precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
                    DesktopWidgetService.shared.sync(model)
                    try? await Task.sleep(for: .milliseconds(600))
                    let size = item.representedObject as! String
                    let expected = PresentationPolicy.widgetSize(size)
                    precondition(panel.frame.width == expected.width && panel.frame.height == expected.height)
                    precondition(abs(panel.frame.minX - topLeft.x) < 1 && abs(panel.frame.maxY - topLeft.y) < 1)
                    capture(panel, "optimization-" + size)
                }
                print("PASS: enabled native size menu actions; all sizes preserve top-left")
                panel.contentView?.perform(NSSelectorFromString("toggleLock")); DesktopWidgetService.shared.sync(model)
                precondition(!panel.isMovable && !panel.isMovableByWindowBackground)
                panel.contentView?.perform(NSSelectorFromString("toggleLock")); DesktopWidgetService.shared.sync(model)
                precondition(panel.isMovable)
                if CGPreflightPostEventAccess() {
                    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate(options: [])
                    panel.setFrameOrigin(NSPoint(x: 250, y: 250))
                    let origin = panel.frame.origin
                    let height = NSScreen.screens[0].frame.maxY
                    let start = CGPoint(x: panel.frame.midX, y: height - panel.frame.midY)
                    let finish = CGPoint(x: start.x + 80, y: start.y - 40)
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: finish, mouseButton: .left)?.post(tap: .cghidEventTap)
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: finish, mouseButton: .left)?.post(tap: .cghidEventTap)
                    }
                    try? await Task.sleep(for: .seconds(1.5))
                    print("Desktop drag: \(origin) -> \(panel.frame.origin)"); fflush(nil)
                    precondition(panel.frame.origin != origin, "Desktop drag failed")
                } else { print("Desktop drag: synthetic input unavailable; interactive level and native drag properties verified"); fflush(nil) }
                // Turning off an already-off panel must not resume a paused group.
                WidgetPreferences.setMaster(false)
                WidgetPreferences.setEnabled(false, kind: .summary)
                DesktopWidgetService.shared.sync(model)
                precondition(!d.bool(forKey: "desktopWidgetsEnabled"))
                precondition(!NSApp.windows.contains { $0.isVisible && $0.frameAutosaveName.hasPrefix("MacPulse.HUD.") })
                WidgetPreferences.setMaster(true); DesktopWidgetService.shared.sync(model)
                // Only selected panels exist; unrelated panels retain their native window identity.
                WidgetPreferences.setEnabled(false, kind: .compute)
                WidgetPreferences.setEnabled(false, kind: .memory)
                DesktopWidgetService.shared.sync(model)
                @MainActor func activePanels() -> [NSWindow] {
                    NSApp.windows.filter { $0.isVisible && $0.frameAutosaveName.hasPrefix("MacPulse.HUD.") }
                }
                precondition(activePanels().count == 1 && activePanels()[0].frameAutosaveName == "MacPulse.HUD.network")
                let retainedNetwork = activePanels()[0]
                model.fullInterfaceVisible = false
                precondition(model.requestedMetrics == [.cpu, .network], "Network HUD must not request memory, GPU, SMC or storage")
                WidgetPreferences.setEnabled(true, kind: .memory); DesktopWidgetService.shared.sync(model)
                precondition(activePanels().count == 2 && activePanels().contains { $0 === retainedNetwork })
                WidgetPreferences.setEnabled(false, kind: .memory)
                WidgetPreferences.setEnabled(false, kind: .network); DesktopWidgetService.shared.sync(model)
                precondition(activePanels().isEmpty && !d.bool(forKey: "desktopWidgetsEnabled"))
                WidgetPreferences.setEnabled(true, kind: .compute); DesktopWidgetService.shared.sync(model)
                precondition(activePanels().count == 1 && WidgetPreferences.enabled == [.compute])
                // Full snapshots are requested only for visual fixtures, outside the selection-policy assertions.
                model.fullInterfaceVisible = true
                try? await Task.sleep(for: .seconds(3))
                for kind in DesktopWidgetKind.allCases {
                    WidgetPreferences.setMaster(false)
                    WidgetPreferences.setEnabled(true, kind: kind)
                    DesktopWidgetService.shared.sync(model)
                    precondition(activePanels().count == 1)
                    let window = activePanels()[0]
                    for size in kind.supportsSmall ? ["small", "medium", "large"] : ["medium", "large"] {
                        d.set(size, forKey: "widgetSize." + kind.rawValue)
                        DesktopWidgetService.shared.sync(model)
                        try? await Task.sleep(for: .milliseconds(500))
                        let expected = PresentationPolicy.widgetSize(size)
                        precondition(window.frame.width == expected.width && window.frame.height == expected.height)
                        capture(window, "widget-" + kind.rawValue + "-" + size)
                    }
                    if kind == .summary {
                        d.set("small", forKey: "widgetSize.summary"); DesktopWidgetService.shared.sync(model)
                        try? await Task.sleep(for: .milliseconds(500))
                        precondition(window.frame.width == 340 && window.frame.height == 160)
                        guard let menu = window.contentView?.perform(NSSelectorFromString("makeContextMenu"))?.takeUnretainedValue() as? NSMenu else { fatalError("Summary menu missing") }
                        precondition(menu.items.last?.submenu?.items.count == 2)
                        precondition(menu.items.last?.submenu?.items.first?.state == .on)
                    }
                }
                precondition(model.widgetHistory.count <= 20)
                print("PASS: independent enable/disable, retained windows, selective collection, eleven widget layouts and summary size restriction"); fflush(nil)
                d.set(false, forKey: "desktopWidgetsEnabled"); DesktopWidgetService.shared.sync(model)
                if let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] {
                    for item in windows where (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == getpid() {
                        if let id = item[kCGWindowNumber as String] as? UInt32 {
                            print("Window", item[kCGWindowName as String] ?? "", item[kCGWindowBounds as String] ?? "", item[kCGWindowLayer as String] ?? "")
                            captureID(id, "optimization-menubar-" + String(id))
                        }
                    }
                }
                if CommandLine.arguments.contains("--ui-only") {
                    await model.stop()
                    for (index, key) in keys.enumerated() { if let value = old[index] { d.set(value, forKey: key) } else { d.removeObject(forKey: key) } }
                    print("PASS: UI-only check"); exit(0)
                }
                model.fullInterfaceVisible = true
                print("Begin full collection baseline"); fflush(nil)
                let baseline = await measure(30)
                model.fullInterfaceVisible = false; model.fans.interfaceVisible = false
                precondition(model.requestedMetrics == .cpu)
                try? await Task.sleep(for: .seconds(3))
                print("Begin selective background measurement"); fflush(nil)
                let optimized = await measure(60)
                print(String(format: "CPU full collection %.3f%%; selective background %.3f%%; RSS high-water %.1f MB", baseline, optimized, Double(usage().ru_maxrss) / 1e6))
                precondition(model.history.count <= 20)
                await model.stop()
                for (index, key) in keys.enumerated() { if let value = old[index] { d.set(value, forKey: key) } else { d.removeObject(forKey: key) } }
                print("PASS: scroll, all widget sizes, lock and bounded history")
                exit(0)
            }
        }.defaultSize(width: 1040, height: 650)
    }
    func usage() -> rusage { var value = rusage(); getrusage(RUSAGE_SELF, &value); return value }
    func seconds(_ value: rusage) -> Double { Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec) + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1e6 }
    func measure(_ duration: Double) async -> Double {
        let start = seconds(usage()), time = ProcessInfo.processInfo.systemUptime
        try? await Task.sleep(for: .seconds(duration))
        return (seconds(usage()) - start) / (ProcessInfo.processInfo.systemUptime - time) * 100
    }
    func capture(_ window: NSWindow, _ name: String) { captureID(CGWindowID(window.windowNumber), name) }
    func captureID(_ id: CGWindowID, _ name: String) {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: ".build/\(name).png"))
    }
}

private struct OptimizationLauncher: View {
    let model: MonitorModel
    @Environment(\.openWindow) private var openWindow
    var body: some View { MenuBarLabel(model: model).onAppear { openWindow(id: "dashboard") } }
}
