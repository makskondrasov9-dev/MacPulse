import Foundation

/// UI-only caches; Foundation's mutable formatter objects never cross the main actor.
@MainActor enum ViewFormatters {
    private static var durations: [String: DateComponentsFormatter] = [:]
    private static var relatives: [String: RelativeDateTimeFormatter] = [:]
    static func duration(_ seconds: Double, locale: Locale) -> String {
        let formatter: DateComponentsFormatter
        if let cached = durations[locale.identifier] { formatter = cached }
        else {
            formatter = DateComponentsFormatter(); formatter.allowedUnits = [.hour, .minute, .second]; formatter.unitsStyle = .abbreviated
            var calendar = Calendar.current; calendar.locale = locale; formatter.calendar = calendar
            durations[locale.identifier] = formatter
        }
        return formatter.string(from: seconds) ?? "—"
    }
    static func relative(_ date: Date, locale: Locale) -> String {
        let formatter: RelativeDateTimeFormatter
        if let cached = relatives[locale.identifier] { formatter = cached }
        else {
            formatter = RelativeDateTimeFormatter(); formatter.locale = locale; formatter.unitsStyle = .full
            relatives[locale.identifier] = formatter
        }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
