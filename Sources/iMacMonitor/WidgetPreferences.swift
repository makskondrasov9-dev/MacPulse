import Foundation
import MonitorCore
import SwiftUI

@MainActor enum WidgetPreferences {
    static func choices(_ defaults: UserDefaults = .standard) -> [DesktopWidgetKind: Bool] {
        var result: [DesktopWidgetKind: Bool] = [:]
        for kind in DesktopWidgetKind.allCases {
            if let value = defaults.object(forKey: "widgetEnabled." + kind.rawValue) as? Bool { result[kind] = value }
        }
        return result
    }
    static var enabled: Set<DesktopWidgetKind> {
        guard UserDefaults.standard.bool(forKey: "desktopWidgetsEnabled") else { return [] }
        return DesktopWidgetPolicy.enabled(master: true, choices: choices())
    }
    static func setEnabled(_ enabled: Bool, kind: DesktopWidgetKind) {
        let defaults = UserDefaults.standard
        let wasEnabled = defaults.bool(forKey: "desktopWidgetsEnabled")
        // An explicit choice made while all panels are off should enable only that panel.
        if enabled && !wasEnabled {
            for other in DesktopWidgetKind.allCases { defaults.set(false, forKey: "widgetEnabled." + other.rawValue) }
        }
        defaults.set(enabled, forKey: "widgetEnabled." + kind.rawValue)
        let anySelected = !DesktopWidgetPolicy.enabled(master: true, choices: choices()).isEmpty
        defaults.set((wasEnabled || enabled) && anySelected, forKey: "desktopWidgetsEnabled")
    }
    static func setMaster(_ enabled: Bool) {
        let defaults = UserDefaults.standard
        if enabled && DesktopWidgetPolicy.enabled(master: true, choices: choices()).isEmpty {
            defaults.set(true, forKey: "widgetEnabled.compute")
        }
        defaults.set(enabled, forKey: "desktopWidgetsEnabled")
    }
    static var metrics: MetricSelection {
        enabled.reduce(into: MetricSelection()) { result, kind in
            result.formUnion(kind.metrics)
            if kind == .compute && size(kind) == "large" { result.insert(.cpuDetails) }
        }
    }
    static func size(_ kind: DesktopWidgetKind) -> String {
        kind.normalizedSize(UserDefaults.standard.string(forKey: "widgetSize." + kind.rawValue) ?? "medium")
    }
}
