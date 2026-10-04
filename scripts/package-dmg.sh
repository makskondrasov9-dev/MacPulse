#!/bin/bash
# Package the already built application for installation through Finder.
set -euo pipefail
cd "$(dirname "$0")/.."
APP_DIR="$PWD/dist/MacPulse.app"
if [[ ! -d "$APP_DIR" ]]; then
    bash scripts/build-app.sh
fi
codesign --verify --strict "$APP_DIR"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/iMacMonitor-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$APP_DIR" "$STAGING_DIR/MacPulse.app"
ln -s /Applications "$STAGING_DIR/Applications"
cat > "$STAGING_DIR/Установка.txt" <<'TEXT'
Установка MacPulse

1. Перетащите MacPulse в папку Applications («Программы»).
2. Откройте MacPulse из «Программ».
3. Нажмите на показатель CPU в строке меню и выберите «Открыть MacPulse».

Требуется macOS 14 Sonoma или новее. Один установщик для Intel и Apple Silicon.

Первый запуск

Эта версия пока не подписана сертификатом Developer ID и не заверена Apple.
Если macOS блокирует запуск, после попытки открыть приложение перейдите в
Системные настройки → Конфиденциальность и безопасность → Всё равно открыть.
Разрешайте запуск только если доверяете источнику загрузки.
Отключать защиту macOS или вводить команды в Терминале не нужно.

Очистка

«Быстрая очистка» сразу удаляет доступные кэши, логи и содержимое Корзины.
Для выбора категорий используйте ручную очистку. Закройте приложения,
кэш которых хотите очистить. Полный доступ к диску включается по желанию
через раздел «Настройки» MacPulse; без него часть файлов будет пропущена.

Язык

Откройте Настройки → Язык приложения. Доступны 12 языков и выбор языка системы.
Изменение применяется сразу.

Обновление

Завершите MacPulse через меню приложения перед заменой новой версией.
Если раньше устанавливали iMacMonitor, удалите старое приложение из «Программ»,
чтобы не запускать две копии. Настройки сохраняются.

TEXT
cat > "$STAGING_DIR/Install.txt" <<'TEXT'
Install MacPulse

1. Drag MacPulse to Applications.
2. Open MacPulse from Applications.
3. Click the CPU indicator in the menu bar and choose Open MacPulse.

Requires macOS 14 Sonoma or later. One installer for Intel and Apple Silicon.
Choose your language in Settings → Application language. Twelve languages are
included, plus Follow system. Changes apply immediately.

First launch

This release does not have a Developer ID signature or Apple notarization.
If macOS blocks it, try opening the app, then go to System Settings →
Privacy & Security → Open Anyway. Only proceed if you trust the download.
You do not need Terminal commands or to disable macOS security.

Updating

Quit the running MacPulse before replacing it. Your preferences are preserved.
If you still have an old iMacMonitor.app, remove that copy to avoid running both.

Cleanup and control

Quick Clean permanently empties accessible Trash items along with caches and logs.
Use manual cleanup to choose categories. Close apps whose caches you want to clean.
Full Disk Access is optional; inaccessible files are skipped.
Process termination always requires confirmation. Unsaved changes can be lost.
Custom fan control is supported on verified Intel hardware; Apple Silicon is
read-only. macOS retains the ability to increase fan speed for cooling.
TEXT
hdiutil create -volname MacPulse -srcfolder "$STAGING_DIR" \
    -format UDZO -ov "$PWD/dist/MacPulse.dmg"
