# MacPulse 1.0 architecture

## Desktop HUDs

`DesktopWidgetService` is a MainActor AppKit window coordinator. It owns three nonactivating, borderless NSPanel instances with SwiftUI content. The panels observe the existing `MonitorModel`; they do not create polling loops. Charts use only the latest twelve samples. UserDefaults stores enablement, level, opacity and click-through settings; NSWindow frame autosave restores each panel independently. Off-screen saved frames are brought back to a visible display on creation. Shutdown closes panels and removes notification observers.

`DesktopHUD` renders CPU/GPU, RAM/disk and network panels. `DesktopWidgetSettings`, the menu-bar toggle and main-window toggle share AppStorage keys. Click-through can always be disabled from Settings even when panels ignore mouse events.

## Network processes

`NetworkProcessMonitorService` is an actor using the existing bounded, cancellable `DiagnosticProcess` runner. It executes `/usr/sbin/lsof -n -P -iTCP -iUDP -F0pcfPnT` without a shell or elevated permissions. The runner limits output to 2 MB, times out after five seconds, and reaps canceled children. `ConnectionParser` consumes tagged NUL/newline fields, resets file/process state and deduplicates rows. IPv6 endpoints stay intact; DNS resolution is disabled.

`NetworkProcessModel` polls with a three-second delay between completed reads. `NetworkProcessesView.task` owns the lifecycle, so leaving the tab cancels collection. Search and active-remote filtering are local. Permission failures clear stale data and show a neutral error. Visibility is not a guarantee of complete system-wide traffic coverage.

## Usage and peaks

`InsightsModel` receives NSWorkspace application-activation notifications. `ForegroundUsageTracker` splits intervals at each event and flushes them on the existing metric tick. Late samples cannot rewind its timeline. `DailyUsage` handles the day boundary and rejects sleep/poll gaps over ten seconds. Idle/session eligibility remains an explicit gate. Persistence uses the existing serialized AnalyticsStore; disabling tracking resets the timeline.

`SessionPeaks` changes the CPU timestamp only when a strictly higher valid temperature arrives. Equal, lower and invalid values retain the original record. Missing sensors stay missing.

## Validation

- 112 tests: 106 regular checks and six opt-in hardware/network tests.
- Parser tests cover field framing, IPv6, UDP, state resets, malformed data, duplicates and search.
- Usage tests cover subsecond app switches, idle/sleep exclusion and stale samples; peak tests cover timestamp stability.
- `bash scripts/check-flagship.sh` runs a native UI smoke test for panel levels, opacity, click-through, restored positions and a live socket read. It restores widget settings on success; screenshots remain in ignored `.build/`.
- Local runtime checks use Intel Sonoma. Cross-compilation does not replace hardware validation on Apple Silicon or runtime checks on Ventura.
