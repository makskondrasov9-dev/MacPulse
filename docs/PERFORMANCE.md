# UI and background performance

122 test cases: 116 regular checks pass; six hardware/network opt-ins remain separate. All 494 messages pass the twelve-language validator. The combined production status-image renderer preserves both charts and the entire text as one non-template image: 290.5 × 16 pt, with 2,309 colored text pixels in each appearance in the regression fixture.

## Collection policy

`MetricCollector.sample(selection:)` executes only requested service calls. A visible, unminimized main window, open metrics popover or active diagnostic benchmark requests the full snapshot. HUDs request only the union of enabled panel requirements plus visible menu metrics, without process enumeration or battery sampling. The large compute panel also requests OS CPU power-limit information. With these closed, `MonitorModel.requestedMetrics` derives CPU/RAM/GPU/CPU-temperature/network needs from the current text/chart settings. Identity polling is independent, enabled only for visible UI or IP/VPN settings (and explicit public-IP history).

CPU-only menu monitoring skips process enumeration, GPU registry walks, battery, SMART, storage and SMC. Temperature-only menu monitoring queries four CPU keys instead of the complete sensor list. Polls remain sequential with timer tolerance. Background cadence is three seconds; foreground cadence retains the user's 1–3 second setting.

Fan telemetry is reduced to a 15-second cadence when its view is hidden and no control session exists. Any active/authorizing helper session keeps the two-second heartbeat. The privileged helper and its safety policy are unchanged.

## Presentation

The dashboard uses static HStack rows inside VStack, with a two/three-column width breakpoint. Missing metric cards keep stable identities and collapse with clipping. A native scroll anchor restores a valid offset after disclosure changes and sidebar navigation. The model retains the user scroll offset independently of dashboard view lifetime; attachment and disclosure guards keep transient layout values from replacing it. Its observer belongs to the scroll document, suspends dashboard publishing during native live/inertial scrolling, and applies only the latest pending sample on completion. A closed or occluded dashboard retains its layout and last data without receiving menu ticks. Whole-percentage signatures prevent redundant card-body updates. History is bounded to 20 points and sparkline rendering consumes twelve points. Tiny menu images are cached until input readings actually change. Colored modes retain attributed text as a cached non-template image so status-item template rendering does not discard the chosen colors; monochrome keeps native text.

Mutable UI formatters are cached on MainActor. File-size formatting uses Foundation format styles without allocating ByteCountFormatter on each call. Session peaks and usage publish only changes.

## Desktop interaction

Wallpaper level + 1 is below Finder's desktop-icons hit-test window on some macOS versions. Interactive HUDs use the higher of wallpaper+1 and desktop-icons+1, remaining below regular app windows. Click-through HUDs use wallpaper+1. The native hosting view owns the HUD hit area and uses NSWindow.performDrag; lock changes native movement flags without disabling right-click menus.

Context-menu sizes are 160×160, 340×160 and 340×340 points. Root and size menus disable automatic responder validation; every native item has an enabled target/action. Animated physical resizing preserves the top-left corner. The same per-widget sizes and lock controls appear in the Widgets settings tab. Each HUD persists its own size and lock state; existing frame autosave names are retained. The material has a 22-point continuous rounded shape and a 0.5-point white border at 12% opacity.

## Reproduction

`bash scripts/check-optimization.sh` opens the native UI, checks scroll offset, three HUD sizes and lock state, and attempts a desktop drag when synthetic input is authorized. It compares process user+system CPU over a 30-second full-collection phase and a 60-second selective phase with CPU-only menu text. Maximum RSS is reported separately. Widget/menu settings are restored on successful completion; private captures remain in ignored `.build/`.

Percent CPU uses one fully occupied logical core as 100%. Results depend on selected menu sensors, live diagnostics, hardware and system load; no constant CPU guarantee is assumed.

## Measured packaged Release apps (Intel iMac / Sonoma)

Earlier two-second sampling measurements, with CPU-only menu settings; main window closed, HUDs and public-IP tracking disabled. Eight seconds of warm-up excluded. Process user+system CPU counters were read with `ps` (100% means one fully occupied core).

| Build | Measurement | CPU | RSS at end |
|---|---|---|---|
| 1.0.0 / 17 | 30 s | 0.733% | 28.4 MiB |
| 1.0.1 / 18 · monochrome | 60 s | 0.250% | 27.5 MiB |
| 1.0.1 / 18 · category colors | 30 s | 0.300% | 29.2 MiB |

RSS changed by +0.1 MiB over the monochrome 60-second measurement and +0.5 MiB over the 30-second color measurement. This is a bounded short-run observation, not a long-duration leak proof. GPU/sensor/color/chart choices and active UI may increase cost. The unoptimized debug UI harness consumed substantially more and is not used for the release CPU claim.

UI checks verified all three sizes, lock/unlock, first-click acceptance and the Finder-relative level. Synthetic system input was not authorized, so physical desktop dragging still needs a manual check. The scheduling harness is not a display-linked proof of constant 60 fps.

### API references

- [Apple: AttributedString](https://developer.apple.com/documentation/foundation/attributedstring)
- [Apple: NSImage.isTemplate](https://developer.apple.com/documentation/appkit/nsimage/istemplate)

## Interface regression check

`bash scripts/check-optimization.sh --ui-only` exercises real AppKit/SwiftUI windows:

- native sidebar navigation to Settings and back retains 334 pt scroll offset (including non-gesture scrolling); hiding genuinely unavailable cards reduces document height from 1853 to 1322.5 pt while retaining 250 pt;
- the native settings TabView exposes exactly four tabs, with captures for each;
- menu update/validation leaves every size item enabled; actions sent through NSApplication resize the panel to all three sizes and retain its top-left corner;
- colored CPU/network sparklines and the full text are rendered into one original status image, checked in light and dark appearances;
- native first-click hit-testing, movement-lock flags and the Finder-interactive desktop level pass.

Synthetic desktop dragging requires macOS input permission, unavailable to the test process here. The check reports this limitation instead of claiming an automated physical drag. Scheduling samples are a smoke diagnostic, not a display-frame-rate guarantee.

## Final UI-fix build: three-second background cadence

Packaged Universal 1.0.1 / build 18, measured on the Intel iMac with the main window/popover closed, HUDs, public-IP history and app-usage tracking off. CPU is the only selected sensor. Eight-second warm-up is excluded; the process user+system counters use one logical core as 100%.

| Menu presentation | Measurement | CPU | RSS at end | RSS change |
|---|---|---|---|---|
| Monochrome text | 60 s | 0.200% | 27.7 MiB | +0.1 MiB |
| Category colors, CPU chart + text | 120 s | 0.250% | 31.8 MiB | +1.2 MiB |

Reproduce with `python3 scripts/measure-background.py dist/MacPulse.app 60 mono` and `python3 scripts/measure-background.py dist/MacPulse.app 120 category chartAndText`. More selected services, enabled widgets and visible interfaces can increase cost. These short observations do not prove long-term absence of memory leaks or a universal CPU ceiling. Visible interfaces retain the configured 1–3 second cadence; active fan-control heartbeats remain unchanged.


The specialized-widget checks additionally verify independent enable/disable, retaining an unrelated native panel, eleven kind/size layouts, the Summary small-size restriction, and rendered chart-region colors for all four palettes. See [widget architecture](DESKTOP_WIDGETS.md). Their shared minute history is capped at 20 buckets; no per-panel timer is introduced.


### Independent-widget architecture build

Final Universal package after the per-widget refactor: CPU-only category-colored chart + text, panels/main window/popover off, 3-second background cadence. A 60-second packaged-process measurement after eight seconds warm-up observed **0.300% of one core**, RSS **32.3 MiB**, change **+1.3 MiB**. The preceding run observed 0.283%; these short samples vary and do not establish a strict CPU ceiling. The new history remains bounded at 20 buckets and no additional polling timer is introduced. Active panels request their corresponding services and can consume more than this menu-only mode.
