<div align="center">
  <img src="Assets/AppIcon.png" width="112" alt="MacPulse icon">
  <h1>MacPulse 0.8.0</h1>
  <p>A native Mac monitor, cleaner and app uninstaller.<br>Нативный монитор Mac, клинер и деинсталлятор.</p>

  <a href="https://github.com/makskondrasov9-dev/MacPulse/releases"><img src="https://img.shields.io/github/v/release/makskondrasov9-dev/MacPulse" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Universal-x86__64%20%2F%20arm64-blueviolet" alt="Universal Binary x86_64 / arm64">
  <img src="https://img.shields.io/badge/Languages-12-green" alt="12 languages">
  <a href="https://github.com/makskondrasov9-dev/MacPulse/actions/workflows/ci.yml"><img src="https://github.com/makskondrasov9-dev/MacPulse/actions/workflows/ci.yml/badge.svg" alt="Build and tests"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License"></a>
</div>

<p align="center"><a href="#english">English</a> · <a href="#русский">Русский</a> · <a href="#languages--языки">Languages / Языки</a></p>

## English

**[Download the latest MacPulse.dmg](https://github.com/makskondrasov9-dev/MacPulse/releases/latest/download/MacPulse.dmg)** · [Release notes](https://github.com/makskondrasov9-dev/MacPulse/releases) · [Changelog](CHANGELOG.md)

### Features

| Module | What it does |
| --- | --- |
| System monitor | CPU, memory, storage, multiple GPUs, network rates and session totals. Battery appears only on supported laptops. |
| Menu bar | Classic or compact text, CPU/network sparklines, or chart + text. Choose each metric; classic text remains the default. |
| Fans | Read available fan sensors. Supported Intel Macs can use automatic mode, a minimum speed or a temperature curve. |
| Smart Cleaner | Quick cleanup and an itemized manual mode for browser caches, video/audio tools, games, development tools, logs and Trash. |
| App Uninstaller | Discover apps in Applications or drop an .app. Preview the bundle and matching user-library files, review sizes and confirm permanent removal. |
| SSD health | Show available SMART status, remaining life and lifetime writes for supported NVMe and Samsung 860/870 EVO SATA drives. Unsupported readings stay hidden. |
| Preferences | 12 languages, light/dark/system appearance, native launch at login and adjustable polling interval. |

### Install or update

1. Download **MacPulse.dmg** from the latest release.
2. Quit your existing MacPulse before updating.
3. Open the DMG and drag **MacPulse** into **Applications**, replacing the previous version if needed.
4. Open MacPulse. Click its menu bar indicator → **Open MacPulse**.

Requires **macOS Sonoma 14 or later**. One installer supports Intel and Apple Silicon. No Terminal, Xcode or account is needed. Your preferences survive updates.

The app currently uses an ad-hoc signature; it does **not** have Developer ID signing or Apple notarization. If macOS blocks it, try opening it, then use **System Settings → Privacy & Security → Open Anyway**, only if you trust the download. [Apple's instructions](https://support.apple.com/102445). Release assets include `SHA256SUMS`.

### Know what is removed

- Quick Clean permanently empties accessible Trash items along with caches and logs. Use manual cleanup to choose categories.
- The uninstaller removes **only checked paths**. App data can contain projects, documents and settings. Name-only matches start unchecked; shared folders and unidentified leftovers are preserved. It cannot guarantee that every file an app has ever created will be found.
- System apps, MacPulse itself and running apps are protected. No privilege escalation is used for uninstalling. Files that changed after preview require another scan.
- Full Disk Access is optional. Protected containers may be inaccessible; the preview reports skipped paths.

### Hardware and measurement notes

Monitoring has been exercised on an Intel iMac 2017. Available GPU, fan and SMART counters depend on the device, driver and adapter. Apple Silicon fan control remains read-only. SMART is read for the **boot volume's physical drive**, at most once every five minutes; USB adapters may not expose it. Estimated remaining life is a vendor metric, not a guarantee against failure.

Network totals include local traffic on active physical Wi-Fi/Ethernet interfaces. VPN and loopback counters are excluded to prevent double counting. Totals reset when MacPulse restarts. The network sparkline combines incoming and outgoing traffic and scales to its last 12 samples.

## Русский

**[Скачать актуальный MacPulse.dmg](https://github.com/makskondrasov9-dev/MacPulse/releases/latest/download/MacPulse.dmg)** · [Версии и обновления](https://github.com/makskondrasov9-dev/MacPulse/releases) · [История изменений](CHANGELOG.md)

### Возможности

| Раздел | Что умеет |
| --- | --- |
| Монитор | CPU, RAM, диск, несколько видеокарт, скорости сети и трафик за сессию. Аккумулятор отображается только на ноутбуках с доступными показаниями. |
| Строка меню | Классический или компактный текст, микро-графики CPU/сети либо график с текстом. Стиль и показатели выбирает пользователь. |
| Вентиляторы | Показания датчиков; на поддерживаемых Intel Mac — автоматика, минимальные обороты и температурная кривая. |
| Клинер | Быстрая очистка и ручной выбор: браузеры, видео/аудио, игры, инструменты разработки, логи и Корзина. |
| Деинсталлятор | Список приложений и Drag & Drop .app. Предпросмотр приложения и найденных данных, размеры, чекбоксы и подтверждение удаления. |
| Здоровье SSD | Доступный SMART-статус, оставшийся ресурс и записанные терабайты для поддерживаемых NVMe и Samsung 860/870 EVO SATA. |
| Настройки | 12 языков, светлая/тёмная/системная тема, автозапуск и частота опроса. |

### Установка и обновление

1. Скачайте **MacPulse.dmg** из последнего релиза.
2. Перед обновлением завершите работающий MacPulse через меню приложения.
3. Откройте DMG и перетащите **MacPulse** в **Программы / Applications**, при необходимости заменив предыдущую версию.
4. Запустите приложение и нажмите на показатель в строке меню → **Открыть MacPulse**.

Нужна **macOS 14 Sonoma или новее**. Один установщик для Intel и Apple Silicon. Терминал, Xcode и регистрация не требуются. Настройки сохраняются.

Приложение пока без Developer ID и нотариального заверения Apple. Если macOS блокирует запуск, после попытки открытия перейдите в **Системные настройки → Конфиденциальность и безопасность → Всё равно открыть**, если доверяете источнику. [Инструкция Apple](https://support.apple.com/102445). В релизе также есть `SHA256SUMS`.

### Удаление данных и совместимость

- Быстрая очистка безвозвратно удаляет доступное содержимое Корзины, кэши и логи. Для выбора категорий используйте ручной режим.
- Деинсталлятор удаляет **только отмеченные пути**. В данных приложения могут быть проекты, документы и настройки. Совпадения только по названию изначально выключены; общие и неизвестные папки сохраняются. Поиск абсолютно всех файлов, созданных приложением, не гарантируется.
- Системные и запущенные приложения, а также MacPulse защищены. Повышение прав не используется. Если файлы изменились после предпросмотра, нужно повторить сканирование.
- Полный доступ к диску необязателен. Недоступные контейнеры и пути перечисляются в предпросмотре.
- Мониторинг проверялся на Intel iMac 2017. Показатели зависят от драйверов и оборудования. На Apple Silicon вентиляторы доступны только для чтения.
- SMART относится к физическому диску **загрузочного тома** и читается не чаще раза в пять минут. USB-переходники могут его не предоставлять. Оставшийся ресурс — оценка накопителя; неподдерживаемый бейдж скрывается.
- Сеть учитывает локальный трафик физических интерфейсов без повторного прибавления VPN/loopback. Счётчики сессии обнуляются при перезапуске. График сети показывает сумму входящей и исходящей скорости за последние 12 замеров.

## Languages / Языки

| Language | Native name | Locale |
| --- | --- | --- |
| English | English | `en` |
| Russian | Русский | `ru` |
| Spanish | Español | `es` |
| French | Français | `fr` |
| German | Deutsch | `de` |
| Portuguese (Brazil) | Português (Brasil) | `pt-BR` |
| Italian | Italiano | `it` |
| Chinese (Simplified) | 简体中文 | `zh-Hans` |
| Japanese | 日本語 | `ja` |
| Korean | 한국어 | `ko` |
| Arabic | العربية | `ar` |
| Hindi | हिन्दी | `hi` |

Choose a language in Settings; **Follow system** is also available. Arabic uses a right-to-left layout. Translations were prepared with AI assistance and terminology edits, and have not all been reviewed by native speakers. Thanks to the MacPulse contributors; corrections are welcome through issues or pull requests.

Выбор языка доступен в настройках, включая «Как в системе». Арабский интерфейс отображается справа налево. Переводы подготовлены с помощью ИИ и редактурой терминов; вычитка носителями всех языков пока не завершена. Спасибо участникам MacPulse — исправления можно предложить через Issues или Pull Request.

## Development / Разработка

Swift 6 · SwiftUI · IOKit · Mach/Darwin · Swift Package Manager.

[Build and test instructions](docs/DEVELOPMENT.md) · [Uninstaller architecture](docs/UNINSTALLER.md) · [MIT License](LICENSE)

```sh
bash scripts/swift-local.sh test
bash scripts/build-app.sh
bash scripts/package-dmg.sh
```

Tests use temporary fixture apps and files; they do not uninstall your apps or clean your real caches. Hardware checks are opt-in. Contributions and reproducible bug reports are welcome.
