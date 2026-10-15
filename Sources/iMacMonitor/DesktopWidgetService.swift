import AppKit
import MonitorCore
import SwiftUI

@MainActor final class DesktopWidgetService {
    static let shared = DesktopWidgetService()
    private var panels: [NSPanel] = []
    private var kinds: [String: DesktopWidgetKind] = [:]
    private var observer: NSObjectProtocol?
    private weak var model: MonitorModel?
    private var configuration: Configuration?
    private struct Configuration: Equatable {
        let enabled: Set<DesktopWidgetKind>
        let floating: Bool
        let clickThrough: Bool
        let opacity: Double
        let layouts: [String]
        @MainActor init() {
            let defaults = UserDefaults.standard
            layouts =
                DesktopWidgetKind.allCases.map { defaults.string(forKey: "widgetSize." + $0.rawValue) ?? "medium" }
                + DesktopWidgetKind.allCases.map { String(defaults.bool(forKey: "widgetLocked." + $0.rawValue)) }
            enabled = WidgetPreferences.enabled
            floating = defaults.bool(forKey: "desktopWidgetsFloating")
            clickThrough = defaults.bool(forKey: "desktopWidgetsClickThrough")
            let raw = defaults.object(forKey: "desktopWidgetsOpacity") as? Double ?? 0.85
            opacity = raw.isFinite ? min(1, max(0.4, raw)) : 0.85
        }
    }
    func sync(_ model: MonitorModel) {
        self.model = model
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { if let self, let model = self.model { self.sync(model) } }
            }
        }
        let next = Configuration()
        guard next != configuration else { return }
        configuration = next
        guard !next.enabled.isEmpty else {
            closePanels()
            return
        }
        for panel in panels where kinds[panel.frameAutosaveName].map({ !next.enabled.contains($0) }) ?? true {
            let name = panel.frameAutosaveName
            panel.saveFrame(usingName: name)
            kinds.removeValue(forKey: name)
            panel.close(); panel.contentView = nil
        }
        panels.removeAll { kinds[$0.frameAutosaveName] == nil }
        for (index, kind) in DesktopWidgetKind.allCases.enumerated() where next.enabled.contains(kind) {
            if !panels.contains(where: { kinds[$0.frameAutosaveName] == kind }) {
                let panel = NSPanel(
                    contentRect: NSRect(x: 50, y: 150 + index * 190, width: 260, height: 170),
                    styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered,
                    defer: false)
                panel.isReleasedWhenClosed = false
                panel.isFloatingPanel = true
                panel.hidesOnDeactivate = false
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.isMovableByWindowBackground = true
                panel.isMovable = true
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                let host = HUDHostingView(rootView: DesktopHUD(model: model, kind: kind))
                host.kind = kind.rawValue
                panel.contentView = host
                let name = "MacPulse.HUD.\(kind.rawValue)"
                panel.setFrameAutosaveName(name)
                panel.setFrameUsingName(name)
                if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) { panel.center() }
                panels.append(panel)
                kinds[name] = kind
            }
        }
        for panel in panels {
            // Finder has an interactive desktop-icons window above the wallpaper.
            // Keep interactive HUDs above that hit-test layer, below regular apps.
            let wallpaper = Int(CGWindowLevelForKey(.desktopWindow)) + 1
            let interactiveDesktop = max(wallpaper, Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            panel.level =
                next.floating ? .floating : NSWindow.Level(rawValue: next.clickThrough ? wallpaper : interactiveDesktop)
            if let kind = kinds[panel.frameAutosaveName] {
                let d = UserDefaults.standard
                let size = PresentationPolicy.widgetSize(WidgetPreferences.size(kind))
                let locked = d.bool(forKey: "widgetLocked." + kind.rawValue)
                panel.isMovable = !locked
                panel.isMovableByWindowBackground = !locked
                if panel.frame.size != NSSize(width: size.width, height: size.height) {
                    let current = panel.frame
                    let frame = NSRect(x: current.minX, y: current.maxY - size.height,
                                       width: size.width, height: size.height)
                    panel.setFrame(frame, display: true, animate: panel.isVisible)
                    panel.saveFrame(usingName: panel.frameAutosaveName)
                }
            }
            panel.alphaValue = next.opacity
            panel.ignoresMouseEvents = next.clickThrough
            panel.orderFrontRegardless()
        }
    }
    private func closePanels() {
        for panel in panels {
            panel.saveFrame(usingName: panel.frameAutosaveName)
            panel.close()
            panel.contentView = nil
        }
        panels = []
        kinds = [:]
    }
    func stop() {
        closePanels()
        configuration = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        model = nil
    }
}

struct DesktopWidgetSettings: View {
    @AppStorage("desktopWidgetsEnabled") private var enabled = false
    @AppStorage("desktopWidgetsFloating") private var floating = false
    @AppStorage("desktopWidgetsClickThrough") private var clickThrough = false
    @AppStorage("desktopWidgetsOpacity") private var opacity = 0.85
    var body: some View {
        Section(L("Desktop widgets")) {
            Toggle(L("Enable desktop widgets"), isOn: Binding(get: { enabled }, set: { WidgetPreferences.setMaster($0) }))
            Toggle(L("Always on top"), isOn: $floating)
            Toggle(L("Click through widgets"), isOn: $clickThrough)
            Slider(value: $opacity, in: 0.4...1) { Text(L("Opacity")) }
            Text(L("Drag widgets to reposition. Disable click-through here to move them again."))
                .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(DesktopWidgetKind.allCases) { kind in
            WidgetLayoutSettings(kind: kind)
        }
    }
}

private struct WidgetLayoutSettings: View {
    let kind: DesktopWidgetKind
    @AppStorage private var size: String
    @AppStorage private var locked: Bool
    @AppStorage private var selected: Bool
    @AppStorage("desktopWidgetsEnabled") private var master = false
    init(kind: DesktopWidgetKind) {
        self.kind = kind
        _size = AppStorage(wrappedValue: "medium", "widgetSize." + kind.rawValue)
        _locked = AppStorage(wrappedValue: false, "widgetLocked." + kind.rawValue)
        _selected = AppStorage(wrappedValue: kind != .summary, "widgetEnabled." + kind.rawValue)
    }
    var body: some View {
        Section(L10n.text(kind.title)) {
            Toggle(L("Show widget"), isOn: Binding(get: { master && selected }, set: { WidgetPreferences.setEnabled($0, kind: kind) }))
            Picker(L("Size"), selection: Binding(get: { kind.normalizedSize(size) }, set: { size = $0 })) {
                if kind.supportsSmall { Text(L("Small")).tag("small") }
                Text(L("Medium")).tag("medium")
                Text(L("Large")).tag("large")
            }.pickerStyle(.segmented)
            Toggle(L("Lock position"), isOn: $locked)
        }
    }
}

@MainActor private final class HUDHostingView<Content: View>: NSHostingView<Content> {
    var kind = "compute"
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { window?.isMovable ?? false }
    // The HUD contains readouts only. Own the entire hit area for native dragging and menus.
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { if window?.isMovable == true { window?.performDrag(with: event) } }
    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
    }
    @objc func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let locked = UserDefaults.standard.bool(forKey: "widgetLocked." + kind)
        let lock = NSMenuItem(title: L("Lock position"), action: #selector(toggleLock), keyEquivalent: "")
        lock.isEnabled = true
        lock.target = self
        lock.state = locked ? .on : .off
        menu.addItem(lock)
        let sizes = NSMenuItem(title: L("Size"), action: nil, keyEquivalent: "")
        sizes.isEnabled = true
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for (title, value) in [("Small", "small"), ("Medium", "medium"), ("Large", "large")] {
            if value == "small" && kind == "summary" { continue }
            let item = NSMenuItem(title: L10n.text(title), action: #selector(changeSize(_:)), keyEquivalent: "")
            item.isEnabled = true
            item.target = self
            item.representedObject = value
            item.state = WidgetPreferences.size(DesktopWidgetKind(rawValue: kind) ?? .compute) == value ? .on : .off
            submenu.addItem(item)
        }
        sizes.submenu = submenu
        menu.addItem(sizes)
        return menu
    }
    @objc func toggleLock() {
        let key = "widgetLocked." + kind
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
    }
    @objc func changeSize(_ sender: NSMenuItem) {
        if let size = sender.representedObject as? String {
            UserDefaults.standard.set(size, forKey: "widgetSize." + kind)
        }
    }
}
