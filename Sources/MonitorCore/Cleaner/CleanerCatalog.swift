import Foundation

/// Exact user-owned cache/data roots. There is no blanket Application Support permission.
enum CleanerCatalog {
    static func applicationName(_ id: String) -> String {
        ["com.google.Chrome": "Chrome", "com.apple.Safari": "Safari", "com.microsoft.VSCode": "VS Code",
         "com.googlecode.iterm2": "iTerm2", "com.brave.Browser": "Brave", "company.thebrowser.Browser": "Arc",
         "org.mozilla.firefox": "Firefox", "com.microsoft.edgemac": "Edge", "com.operasoftware.Opera": "Opera"][id] ?? id
    }

    static func cacheOwners(_ folder: String) -> [String] {
        switch folder.lowercased() {
        case "code", "com.microsoft.vscode": ["com.microsoft.VSCode"]
        case "iterm2", "com.googlecode.iterm2": ["com.googlecode.iterm2"]
        default: [folder]
        }
    }

    static let browserCaches = [
        "com.apple.Safari", "com.google.Chrome", "Google/Chrome", "com.brave.Browser", "BraveSoftware/Brave-Browser",
        "company.thebrowser.Browser", "Arc", "org.mozilla.firefox", "Firefox", "com.microsoft.edgemac", "Microsoft Edge", "com.operasoftware.Opera"
    ]
    static let chromiumProfiles: [(String, String)] = [
        ("Chrome", "Library/Application Support/Google/Chrome"),
        ("Brave", "Library/Application Support/BraveSoftware/Brave-Browser"),
        ("Arc", "Library/Application Support/Arc/User Data"),
        ("Edge", "Library/Application Support/Microsoft Edge"),
        ("Opera", "Library/Application Support/com.operasoftware.Opera")
    ]
    static let chromiumSiteData = ["Cookies", "Cookies-journal", "Network/Cookies", "Network/Cookies-journal",
                                     "Local Storage", "Session Storage", "IndexedDB", "Service Worker", "WebStorage"]
    static let firefoxSiteData = ["cookies.sqlite", "cookies.sqlite-wal", "cookies.sqlite-shm", "storage", "webappsstore.sqlite"]
    static let knownOwners: [(folder: String, app: String, ids: [String])] = [
        ("LGHUBData", "lghub", ["com.logi.ghub", "com.logitech.ghub"]),
        ("LGHUB", "lghub", ["com.logi.ghub", "com.logitech.ghub"]),
        ("Slack", "Slack", ["com.tinyspeck.slackmacgap"]),
        ("discord", "Discord", ["com.hnc.Discord"]),
        ("Spotify", "Spotify", ["com.spotify.client"]),
        ("com.tdesktop.Telegram", "Telegram", ["org.telegram.desktop", "ru.keepcoder.Telegram"])
    ]

    static func standard() -> [CleanerTarget] {
        var targets: [CleanerTarget] = []
        func add(_ category: CleanerCategory, _ name: String, _ path: String, sensitive: Bool = false, note: String? = nil, owners: [String] = []) {
            targets.append(CleanerTarget(category: category, name: name, relativePath: path,
                                         sensitive: sensitive, note: note, ownerIDs: owners))
        }
        for folder in ["CacheClip", "ProxyMedia"] {
            add(.video, "DaVinci Resolve · \(folder)", "Library/Application Support/Blackmagic Design/DaVinci Resolve/\(folder)",
                sensitive: true, note: "Производные видеофайлы. Для восстановления могут потребоваться исходники и повторный рендер.")
        }
        for folder in ["Media Cache", "Media Cache Files", "Peak Files"] {
            add(.video, "Adobe · \(folder)", "Library/Application Support/Adobe/Common/\(folder)")
        }
        add(.video, "Final Cut Pro · кэш", "Library/Caches/com.apple.FinalCut")
        add(.video, "Blender · кэш", "Library/Application Support/Blender/cache")
        for (name, path) in [("AudioUnits", "com.apple.audiounits.cache"), ("AudioUnitCache", "AudioUnitCache"),
                             ("Logic Pro", "com.apple.logic10"), ("GarageBand", "com.apple.garageband10"),
                             ("Ableton", "Ableton"), ("FL Studio", "com.image-line.FLStudio")] {
            add(.audio, name, "Library/Caches/\(path)")
        }
        add(.audio, "FL Studio · временный кэш", "Library/Application Support/Image-Line/FL Studio/Cache")
        add(.games, "Steam · appcache", "Library/Application Support/Steam/appcache")
        add(.games, "Steam · шейдеры", "Library/Application Support/Steam/steamapps/shadercache")
        add(.games, "Steam · незавершённые загрузки", "Library/Application Support/Steam/steamapps/downloading", sensitive: true,
            note: "Прогресс загрузок будет потерян. Закройте Steam.")
        add(.games, "Epic Games · webcache", "Library/Application Support/Epic/EpicGamesLauncher/Saved/webcache")
        add(.development, "Homebrew · архивы и манифесты", "Library/Caches/Homebrew")
        add(.development, "Xcode · DerivedData", "Library/Developer/Xcode/DerivedData")
        add(.development, "Xcode · Archives", "Library/Developer/Xcode/Archives", sensitive: true,
            note: "Архивы сборок и dSYM. Это не кэш: могут понадобиться для публикации и разбора сбоев.")
        add(.development, "Xcode · DeviceSupport", "Library/Developer/Xcode/iOS DeviceSupport", sensitive: true)
        for (name, path) in [("Telegram", "ru.keepcoder.Telegram"), ("Telegram Desktop", "org.telegram.desktop"),
                             ("Spotify", "com.spotify.client"), ("Slack", "com.tinyspeck.slackmacgap"), ("Discord", "com.hnc.Discord")] {
            add(.media, name, "Library/Caches/\(path)")
        }
        for path in browserCaches { add(.browsers, "Безопасный кэш · \(path)", "Library/Caches/\(path)") }
        // DiagnosticReports is already included in Logs; never count it twice.
        add(.system, "Логи и DiagnosticReports", "Library/Logs")
        add(.system, "Корзина", ".Trash", sensitive: true, note: "Все выбранные файлы будут удалены без возможности восстановления.")
        return targets
    }
}
