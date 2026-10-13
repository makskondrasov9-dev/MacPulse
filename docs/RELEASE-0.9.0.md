## MacPulse 0.9.0 — Diagnostics, network identity & insights

### New
- **Hardware Diagnostics:** cancellable 1 GB disk benchmark with OS cache bypass, 15/30/60-second CPU and Metal GPU tests, temperature/power-limit indicators, and a five-color display inspector (click/Space to advance, Escape to exit).
- **Network:** native networkQuality download/upload, idle latency and RPM; local IP/MAC plus opt-in public-IP history through ipify.
- **IP where you need it:** Monitor's network card and optional menu-bar IP (local or public) and VPN/tunnel indicator, including alongside sparklines.
- **Cleaner presentation:** hide unavailable values, with a separate switch for technical network details. Link-local-only system tunnels are excluded from the compact view.
- **Insights:** session CPU-temperature/RAM/GPU peaks, opt-in foreground-app time and estimated CPU consumers.
- New interface strings translated into all **12 languages**.

### Install
Download **MacPulse.dmg**, quit the previous copy and drag MacPulse to Applications. Preferences are preserved. Minimum **macOS 13 Ventura**, Universal **Intel + Apple Silicon**. `SHA256SUMS` is attached; the project Homebrew cask points to this release.

The app remains ad-hoc signed, without Apple notarization. See the [first-launch instructions](https://github.com/makskondrasov9-dev/MacPulse#gatekeeper--first-launch).

### Validation and limits
The 85-case suite has 80 default checks plus five explicit hardware opt-ins. Local default checks passed; disk/CPU/network, Metal, public-IP and existing live collectors were separately checked on an Intel iMac running Sonoma. The display color/keyboard/mouse smoke check passed. CI runs the default tests natively on Intel and arm64 macOS runners, in addition to building a Universal app. Physical Apple Silicon sensor/display validation and Ventura runtime validation remain outstanding.

The new disk/CPU/Metal/network/insight features have no Intel-only dependency. Numeric temperatures, SMART and some GPU metrics remain hardware-dependent; unsupported values stay hidden, and Apple Silicon uses system thermal state. Existing Apple Silicon manual fan control remains unavailable. Thermal/power limits are indicators, not a measured CPU clock. VPN/tunnel detection does not guarantee that all traffic is protected. Public-IP queries are optional and disclosed; local history is capped at 200 changes.

---

## По-русски

- Новый раздел **«Диагностика»**: тест диска 1 ГБ, CPU/Metal-нагрузка с отменой, проверка экрана.
- Замер сети, история IP, адреса в **«Мониторе»** и в строке меню; отдельный индикатор VPN/туннеля.
- Служебные интерфейсы и пустые значения можно скрыть. `utun` без рабочего адреса не считается признаком активного туннеля.
- Пики сессии, время активных приложений и оценка потребителей CPU.
- **12 языков, macOS 13+, Universal Intel/Apple Silicon.** На Apple Silicon новые тесты используют общие системные API; доступность датчиков по-прежнему зависит от модели.

Обновление: завершите старую копию и перенесите приложение из DMG в «Программы». Проверки выполнены на Intel iMac с Sonoma; отдельного устройства Apple Silicon для аппаратной проверки не было.
