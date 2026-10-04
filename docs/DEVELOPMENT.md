# Разработка MacPulse

Нужны macOS 14+ и Xcode 16 или совместимые Command Line Tools со Swift 6.

```sh
swift build
swift test
bash scripts/build-app.sh
bash scripts/package-dmg.sh
```

Результат: `dist/MacPulse.app` и `dist/MacPulse.dmg`. Приложение Universal: x86_64 + arm64.
Bundle ID `local.iMacMonitor` и имя исполняемого файла сохранены для совместимости настроек.

Если CLT содержит несовместимые интерфейсы PackageDescription или повторный
SwiftBridging, используйте `bash scripts/swift-local.sh build` и `bash scripts/swift-local.sh test`.
Скрипт применяет локальный VFS overlay в `.build`, не изменяя установку Xcode/CLT.
Скрипты упаковки используют этот совместимый запуск автоматически.

## Архитектура

- `Sources/MonitorCore/Services`: сбор системных метрик, SMC, батареи и AMD GPU.
- `MetricCollector`: последовательный сбор снимка вне главного потока.
- `Sources/MonitorCore/Cleaner`: каталог путей, actor сканирования и удаления.
- `Sources/iMacMonitor`: SwiftUI, состояние интерфейса и настройки.
- `Sources/CSystem`: ABI AppleSMC и объявления libproc.
- `Tests/MonitorCoreTests`: метрики, декодирование SMC и безопасность очистки.

Опрос по умолчанию раз в 2 секунды, история ограничена минутой.
CPU процесса: 100% соответствует одному ядру. RAM = Active + Wired + Compressed.
Температуры Intel проверяются на правдоподобие; TH0P — датчик отсека, не SMART SSD.
AMD In-Use VRAM использует `inUseVidMemoryBytes`, исключая повторно используемый пул драйвера.
Объём VRAM пока фиксирован профилем Radeon Pro 570 (4 GiB), а не универсальным обнаружением.
Metal `currentAllocatedSize` не используется как системное потребление GPU: это память одного процесса.

## Проверка

Обычные тесты удаления используют только временные каталоги. Дополнительная проверка
реального оборудования запускается явно:

```sh
IMACMONITOR_HARDWARE_TEST=1 bash scripts/swift-local.sh test --filter HardwareSmokeTests
```

Очистка использует снимок файлов, проверку inode, типа и времён изменения,
O_NOFOLLOW для родителей и атомарное перемещение в закрытый staging-каталог.
Конечные симлинки внутри кэшей удаляются без обхода цели. Изменившиеся объекты,
жёсткие ссылки и неизвестные остатки не удаляются. Пустые каталоги могут остаться.
Папки `.MacPulse-delete-*` исключены из очистки: при сбое в них может находиться файл для восстановления.

## Выпуск

1. Обновить версии в `scripts/build-app.sh` и `CHANGELOG.md`.
2. Выполнить тесты и собрать приложение/DMG.
3. Проверить `codesign --verify --strict dist/MacPulse.app` и `hdiutil verify dist/MacPulse.dmg`.
4. Добавить `MacPulse.dmg` и SHA256SUMS к GitHub Release соответствующего тега.

Текущая подпись ad-hoc не заменяет Developer ID и нотариальное заверение Apple.
Не заявляйте нотариальное заверение до успешного прохождения процедуры и проверки Gatekeeper.
