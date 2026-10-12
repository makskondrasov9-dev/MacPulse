## MacPulse 0.8.1 — Ventura support & easier installation

- Minimum macOS version lowered to **13 Ventura**, with compatible empty states and change handlers.
- Universal **Intel x86_64 + Apple Silicon arm64** DMG.
- New English/Russian README, real interface screenshots and a project-maintained Homebrew cask.
- Includes the monitoring, multi-GPU, fan, cleaner, uninstaller and sparkline features introduced in earlier versions.

### Install

Download **MacPulse.dmg**, open it and drag MacPulse to Applications. Quit the previous copy before replacing it. Settings are preserved.

The app is ad-hoc signed, **not Apple-notarized**. Follow the [first-launch instructions](https://github.com/makskondrasov9-dev/MacPulse#gatekeeper--first-launch) for a trusted download. `SHA256SUMS` is attached.

### Validation and limits

All **69 tests passed** locally; both binary slices target macOS 13. Local runtime checks used an Intel iMac on Sonoma. A dedicated Ventura runtime test and broad Apple Silicon hardware testing remain outstanding. Sensor and SMART availability depends on hardware; Apple Silicon fan control is currently read-only.

---

### По-русски

Минимальная система снижена до **macOS 13 Ventura**. В установщике обе архитектуры: Intel и Apple Silicon. Обновлены README, настоящие скриншоты интерфейса и Homebrew Cask проекта. Все 69 тестов прошли; локальная проверка запуска выполнена на iMac с Sonoma, отдельный запуск на Ventura ещё не проверен.

Для обновления завершите старую копию и перенесите приложение из DMG в «Программы». Настройки сохраняются. Приложение пока без нотариального заверения Apple — инструкция первого запуска находится в README.
