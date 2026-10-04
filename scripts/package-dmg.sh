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

Обновление

Завершите MacPulse через меню приложения перед заменой новой версией.
Если раньше устанавливали iMacMonitor, удалите старое приложение из «Программ»,
чтобы не запускать две копии. Настройки сохраняются.

TEXT
hdiutil create -volname MacPulse -srcfolder "$STAGING_DIR" \
    -format UDZO -ov "$PWD/dist/MacPulse.dmg"
