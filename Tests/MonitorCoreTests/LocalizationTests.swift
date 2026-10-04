import Foundation
import Testing
@testable import MonitorCore

struct LocalizationTests {
    @Test func allTwelveCatalogsHaveMatchingKeysAndArguments() throws {
        let source = try #require(L10n.catalogs["ru"])
        #expect(AppLanguage.allCases.count == 13)
        #expect(source.count > 250)
        let tokens = try NSRegularExpression(pattern: #"\{\d+\}"#)
        func placeholders(_ value: String) -> [String] {
            tokens.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .compactMap { Range($0.range, in: value).map { String(value[$0]) } }.sorted()
        }
        for language in AppLanguage.allCases where language != .system {
            let catalog = try #require(L10n.catalogs[language.rawValue])
            #expect(Set(catalog.keys) == Set(source.keys), "Missing translations: \(language.rawValue)")
            for (key, value) in catalog {
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(placeholders(key) == placeholders(value), "Invalid arguments: \(language.rawValue) / \(key)")
                #expect(!value.contains("MACPULSE_"))
            }
        }
    }
    @Test func languageFallbacks() {
        #expect(AppLanguage.resolve("system", preferred: ["de-DE"]) == .de)
        #expect(AppLanguage.resolve("system", preferred: ["pt-PT"]) == .pt)
        #expect(AppLanguage.resolve("system", preferred: ["zh-TW"]) == .zh)
        #expect(AppLanguage.resolve("system", preferred: ["sv-SE"]) == .en)
        #expect(AppLanguage.resolve("ru", preferred: ["en-US"]) == .ru)
        #expect(AppLanguage.resolve("invalid", preferred: ["ar-SA"]) == .ar)
    }
    @Test func interpolationPreservesLiteralUserData() {
        let output = L10n.render("Запрос завершения отправлен: {0} (PID {1}). Список обновится при следующем опросе.",
                                 arguments: ["example {1} %s", "123"], language: .en)
        #expect(output.contains("example {1} %s"))
        #expect(output.contains("123"))
    }
    @Test func serviceMessagesLocalizeAtDisplayTime() {
        #expect(L10n.text("Сомнительное показание: -7 °C", language: .en) == "Doubtful reading: -7 °C")
        #expect(L10n.text("Безопасный кэш · com.google.Chrome", language: .en) == "Safe cache · com.google.Chrome")
        #expect(L10n.text("/tmp/example: Путь не прошёл проверку безопасности.", language: .en)
            == "/tmp/example: The path has not passed the security check.")
        #expect(L10n.text("Сканирование · Корзина", language: .en) == "Scanning · Trash")
    }
    @Test func processDescriptionsDoNotInventUnknownPurpose() {
        var process = ProcessMetrics(pid: 987, name: "unknown-example", cpu: 1, residentBytes: 1024)
        process.ownerUID = 501
        process.executablePath = "/usr/local/bin/example"
        #expect(!process.isSystem)
        #expect(ProcessControlService.description(for: process).contains("Проверьте путь"))
    }
}
