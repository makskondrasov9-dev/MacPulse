import Foundation

public enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
    case system, en, ru, es, fr, de, pt = "pt-BR", it, zh = "zh-Hans", ja, ko, ar, hi
    public var id: String { rawValue }
    public var nativeName: String {
        switch self {
        case .system: L("Как в системе")
        case .en: "English"
        case .ru: "Русский"
        case .es: "Español"
        case .fr: "Français"
        case .de: "Deutsch"
        case .pt: "Português (Brasil)"
        case .it: "Italiano"
        case .zh: "简体中文"
        case .ja: "日本語"
        case .ko: "한국어"
        case .ar: "العربية"
        case .hi: "हिन्दी"
        }
    }
    public static func resolve(_ preference: String, preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        if let explicit = Self(rawValue: preference), explicit != .system { return explicit }
        for identifier in preferred {
            let base = identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? ""
            if base == "pt" { return .pt }
            if base == "zh" { return .zh }
            if let match = Self(rawValue: base), match != .system { return match }
        }
        return .en
    }
}

/// Explicit resources work for both SwiftPM and the standalone app. No global AppleLanguages override.
public enum L10n {
    public static var language: AppLanguage {
        AppLanguage.resolve(UserDefaults.standard.string(forKey: "appLanguage") ?? "system")
    }
    public static var locale: Locale { Locale(identifier: language.rawValue) }
    private static let resourceBundle: Bundle = {
        let name = "iMacMonitor_MonitorCore.bundle"
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent(name),
            Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources").appendingPathComponent(name)]
        for case let url? in candidates { if let bundle = Bundle(url: url) { return bundle } }
        return Bundle.module
    }()
    public static let catalogs: [String: [String: String]] = {
        var result: [String: [String: String]] = [:]
        for language in AppLanguage.allCases where language != .system {
            if let url = resourceBundle.url(forResource: language.rawValue, withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let values = try? JSONDecoder().decode([String: String].self, from: data) {
                result[language.rawValue] = values
            }
        }
        return result
    }()
    public static func template(_ key: String, language: AppLanguage? = nil) -> String {
        catalogs[(language ?? self.language).rawValue]?[key] ?? catalogs["en"]?[key] ?? key
    }
    public static func render(_ key: String, arguments: [String], language: AppLanguage? = nil) -> String {
        // Replace tokens in one pass: a process name containing "{1}" is always literal data.
        let source = template(key, language: language)
        var result = "", index = source.startIndex
        while index < source.endIndex {
            if source[index] == "{", let end = source[index...].firstIndex(of: "}"),
               let number = Int(source[source.index(after: index)..<end]), arguments.indices.contains(number) {
                result += arguments[number]; index = source.index(after: end)
            } else { result.append(source[index]); index = source.index(after: index) }
        }
        return result
    }
    private struct Pattern: @unchecked Sendable {
        let key: String
        let regex: NSRegularExpression
    }
    private static let patterns: [Pattern] = (catalogs["ru"] ?? [:]).keys.filter { $0.contains("{0}") }.sorted { $0.count > $1.count }.compactMap { key in
        var pattern = NSRegularExpression.escapedPattern(for: key)
        for i in 0..<10 { pattern = pattern.replacingOccurrences(of: NSRegularExpression.escapedPattern(for: "{\(i)}"), with: "(.*?)") }
        guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$", options: [.dotMatchesLineSeparators]) else { return nil }
        return Pattern(key: key, regex: regex)
    }
    /// Core service diagnostics remain stable data until they reach a UI boundary.
    public static func text(_ value: String, language: AppLanguage? = nil) -> String {
        if catalogs["ru"]?[value] != nil { return template(value, language: language) }
        guard value.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil else { return value }
        let range = NSRange(value.startIndex..., in: value)
        for pattern in patterns {
            if let match = pattern.regex.firstMatch(in: value, range: range) {
                let args = (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: value).map { String(value[$0]) } ?? "" }
                return render(pattern.key, arguments: args.map { text($0, language: language) }, language: language)
            }
        }
        if let separator = value.range(of: ": ") {
            let suffix = String(value[separator.upperBound...])
            let translated = text(suffix, language: language)
            if translated != suffix { return String(value[..<separator.upperBound]) + translated }
        }
        for prefix in ["Сканирование · ", "Удаление · "] where value.hasPrefix(prefix) {
            return template(prefix, language: language) + text(String(value.dropFirst(prefix.count)), language: language)
        }
        if value.hasPrefix("Кэш · ") { return template("Кэш · ", language: language) + value.dropFirst("Кэш · ".count) }
        return value
    }
}

public struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public let key: String
    public let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"; arguments.append(String(describing: value))
        }
        public mutating func appendInterpolation(_ value: Double, specifier: String) {
            key += "{\(arguments.count)}"
            arguments.append(String(format: specifier, locale: L10n.locale, value))
        }
    }
}
public func L(_ message: LocalizedMessage) -> String { L10n.render(message.key, arguments: message.arguments) }
