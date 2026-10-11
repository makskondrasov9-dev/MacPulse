# MacPulse 0.8.0

## English

- Four menu bar styles: classic text, compact text, sparklines, and charts with text. Choose CPU and network charts independently; existing text preferences are preserved.
- App Uninstaller: browse installed apps or drop an `.app`, review related files and their sizes, then confirm removal of the selected items. System apps, running apps and MacPulse are protected. Name-only matches start unchecked.
- SSD health: read-only SMART status, remaining life and lifetime writes for supported NVMe and Samsung 860/870 EVO drives. Unsupported drives and USB adapters do not display a health badge.
- Fixed uninstaller layout: a single title, content below the native toolbar, a 280–380 pt app list and a detail area limited to 850 pt.
- All new controls are available in the existing 12 languages. The uninstaller adapts to narrow windows.

Requires macOS 14 or later. `MacPulse.dmg` includes Intel and Apple Silicon binaries. Quit MacPulse, open the DMG and drag MacPulse into Applications to replace the previous version. Preferences are preserved.

This build uses an ad-hoc signature and is not notarized by Apple. If macOS blocks the downloaded app, follow the installation instructions in the README.

Validation: 69 tests passed, including the original 52 tests and read-only hardware checks on an Intel iMac. SMART decoding is also tested with fixtures; hardware coverage does not include every supported drive. Uninstaller deletion tests use temporary applications, not personal data.

## Русский

- Четыре стиля строки меню: классический текст, компактный текст, микро-графики и графики с текстом. Графики CPU и сети выбираются независимо; прежние настройки текста сохраняются.
- Деинсталлятор: выберите установленное приложение или перетащите `.app`, проверьте найденные файлы и размеры, затем подтвердите удаление выбранного. Системные и запущенные приложения, а также MacPulse защищены. Совпадения только по названию изначально не отмечены.
- Здоровье SSD: чтение статуса SMART, оставшегося ресурса и объёма записанных данных для поддерживаемых NVMe и Samsung 860/870 EVO. Для неподдерживаемых накопителей и USB-переходников бейдж скрыт.
- Исправлена вёрстка деинсталлятора: один заголовок, содержимое ниже системной панели, список шириной 280–380 pt и область деталей до 850 pt.
- Новые элементы доступны на всех 12 языках. Деинсталлятор адаптируется к узким окнам.

Требуется macOS 14 или новее. `MacPulse.dmg` содержит версии для Intel и Apple Silicon. Завершите MacPulse, откройте DMG и перетащите приложение в «Программы» с заменой предыдущей версии. Настройки сохраняются.

Сборка подписана локально, без нотариального заверения Apple. Если macOS блокирует скачанное приложение, следуйте инструкции установки в README.

Проверки: прошли 69 тестов, включая исходные 52 и чтение аппаратных метрик на Intel iMac. Декодирование SMART дополнительно проверено на тестовых данных; все модели накопителей физически не проверялись. Удаление в тестах выполнялось только на временных приложениях.
