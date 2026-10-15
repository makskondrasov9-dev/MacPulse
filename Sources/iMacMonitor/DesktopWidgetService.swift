import AppKit
import SwiftUI
import MonitorCore

@MainActor final class DesktopWidgetService {
    static let shared = DesktopWidgetService()
    private var panels: [NSPanel] = []
    private var observer: NSObjectProtocol?
    private weak var model: MonitorModel?
    private var configuration: Configuration?
    private struct Configuration: Equatable {
        let enabled: Bool
        let floating: Bool
        let clickThrough: Bool
        let opacity: Double
        init() {
            let defaults = UserDefaults.standard
            enabled = defaults.bool(forKey: "desktopWidgetsEnabled")
            floating = defaults.bool(forKey: "desktopWidgetsFloating")
            clickThrough = defaults.bool(forKey: "desktopWidgetsClickThrough")
            let raw = defaults.object(forKey: "desktopWidgetsOpacity") as? Double ?? 0.85
            opacity = raw.isFinite ? min(1, max(0.4, raw)) : 0.85
        }
    }
    func sync(_ model: MonitorModel) {
        self.model = model
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self, let model = self.model { self.sync(model) } }
            }
        }
        let next = Configuration()
        guard next != configuration else { return }
        configuration = next
        guard next.enabled else { closePanels(); return }
        if panels.isEmpty {
            for (index, kind) in DesktopHUD.Kind.allCases.enumerated() {
                let panel = NSPanel(contentRect: NSRect(x: 50, y: 150 + index * 190, width: 260, height: 170),
                    styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.isFloatingPanel = true
                panel.hidesOnDeactivate = false
                panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
                panel.isMovableByWindowBackground = true
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                panel.contentView = HUDHostingView(rootView: DesktopHUD(model: model, kind: kind))
                let name = "MacPulse.HUD.\(kind.rawValue)"
                panel.setFrameAutosaveName(name)
                panel.setFrameUsingName(name)
                if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) { panel.center() }
                panels.append(panel)
            }
        }
        for panel in panels {
            panel.level = next.floating ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            panel.alphaValue = next.opacity
            panel.ignoresMouseEvents = next.clickThrough
            panel.orderFrontRegardless()
        }
    }
    private func closePanels() {
        for panel in panels { panel.saveFrame(usingName: panel.frameAutosaveName); panel.close(); panel.contentView = nil }
        panels = []
    }
    func stop() {
        closePanels(); configuration = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil; model = nil
    }
}

private struct DesktopHUD: View {
    enum Kind: String, CaseIterable { case compute, memory, network }
    @ObservedObject var model: MonitorModel
    let kind: Kind
    @AppStorage("appLanguage") private var language = "system"
    @AppStorage("accentColor") private var accent = AppAccent.blue.rawValue
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch kind {
            case .compute:
                HStack { Text("CPU"); Spacer(); Text(MetricFormat.percent(model.snapshot?.cpu?.usage)) }
                wave(model.history.suffix(12).map { $0.cpu })
                HStack { Text("GPU"); Spacer(); Text(MetricFormat.percent(model.snapshot?.gpu.utilization)) }
                wave(model.history.suffix(12).map { $0.gpu })
            case .network:
                Text(L("Сеть")).font(.headline)
                Text("↓ " + ByteSizeFormat.rate(model.snapshot?.network.downloadBytesPerSecond))
                Text("↑ " + ByteSizeFormat.rate(model.snapshot?.network.uploadBytesPerSecond))
            case .memory:
                if let ram = model.snapshot?.memory { Text("RAM · " + ByteSizeFormat.string(ram.used)); ProgressView(value: MetricFormat.ratio(ram.used, ram.total).map { $0 / 100 } ?? 0) }
                if let disk = model.snapshot?.storage { Text(L("Диск") + " · " + ByteSizeFormat.string(disk.used)); ProgressView(value: MetricFormat.ratio(disk.used, disk.total).map { $0 / 100 } ?? 0) }
            }
        }
        .font(.callout.monospacedDigit()).padding(18).frame(width: 260, height: 170)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .tint((AppAccent(rawValue: accent) ?? .blue).color)
        .environment(\.locale, Locale(identifier: AppLanguage.resolve(language).rawValue))
        .environment(\.layoutDirection, AppLanguage.resolve(language) == .ar ? .rightToLeft : .leftToRight)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
    private func wave(_ values: [Double?]) -> some View {
        GeometryReader { geometry in
            Path { path in
                var connected = false
                for (index, value) in values.enumerated() {
                    guard let value, value.isFinite else { connected = false; continue }
                    let point = CGPoint(x: geometry.size.width * Double(index) / Double(max(1, values.count - 1)), y: geometry.size.height * (1 - min(100, max(0, value)) / 100))
                    if connected { path.addLine(to: point) } else { path.move(to: point); connected = true }
                }
            }.stroke((AppAccent(rawValue: accent) ?? .blue).color, lineWidth: 1.5)
        }.frame(height: 22).allowsHitTesting(false)
    }
}

struct DesktopWidgetSettings: View {
    @AppStorage("desktopWidgetsEnabled") private var enabled = false
    @AppStorage("desktopWidgetsFloating") private var floating = false
    @AppStorage("desktopWidgetsClickThrough") private var clickThrough = false
    @AppStorage("desktopWidgetsOpacity") private var opacity = 0.85
    var body: some View {
        Section(L("Desktop widgets")) {
            Toggle(L("Enable desktop widgets"), isOn: $enabled)
            Toggle(L("Always on top"), isOn: $floating)
            Toggle(L("Click through widgets"), isOn: $clickThrough)
            Slider(value: $opacity, in: 0.4...1) { Text(L("Opacity")) }
            Text(L("Drag widgets to reposition. Disable click-through here to move them again."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor private final class HUDHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}
