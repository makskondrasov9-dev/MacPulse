import Foundation

public enum ByteSizeFormat {
    /// Decimal file sizes: KB below 1 MB, MB below 1 GB, then GB.
    /// ByteCountFormatter has no locale property; its modern attributed format
    /// style supplies localized units when the app language differs from macOS.
    public static func string(_ bytes: UInt64, locale: Locale = L10n.locale) -> String {
        let count = Int64(clamping: bytes)
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.isAdaptive = true
        formatter.allowsNonnumericFormatting = false
        formatter.zeroPadsFractionDigits = true
        let units: ByteCountFormatStyle.Units
        let divisor: Double
        let digits: Int
        switch bytes {
        case 0..<1_000: formatter.allowedUnits = .useBytes; units = .bytes; divisor = 1; digits = 0
        case 1_000..<1_000_000: formatter.allowedUnits = .useKB; units = .kb; divisor = 1_000; digits = 0
        case 1_000_000..<1_000_000_000: formatter.allowedUnits = .useMB; units = .mb; divisor = 1_000_000; digits = 1
        default: formatter.allowedUnits = .useGB; units = .gb; divisor = 1_000_000_000; digits = 2
        }
        if locale.identifier == Locale.current.identifier { return formatter.string(fromByteCount: count) }
        return localized(Double(bytes), units: units, divisor: divisor, digits: digits, locale: locale)
    }

    private static func localized(_ bytes: Double, units: ByteCountFormatStyle.Units,
                                  divisor: Double, digits: Int, locale: Locale) -> String {
        let count = Int64(min(bytes, Double(Int64.max - 1024)))
        let formatted = count.formatted(.byteCount(style: .file, allowedUnits: units, spellsOutZero: false).locale(locale).attributed)
        let number = (bytes / divisor).formatted(.number.precision(.fractionLength(digits)).locale(locale))
        var result = "", insertedNumber = false
        for run in formatted.runs {
            if run.byteCount == .value {
                if !insertedNumber { result += number; insertedNumber = true }
            } else { result += String(formatted[run.range].characters) }
        }
        return result
    }

    public static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        let megabytes = value >= 1_000_000
        let reading = localized(value, units: megabytes ? .mb : .kb,
                                divisor: megabytes ? 1_000_000 : 1_000,
                                digits: value == 0 ? 0 : 1, locale: L10n.locale)
        return L("\(reading) / с")
    }
}
