# Desktop widgets and menu chart colors

The desktop panels share the app's existing collection loop. They do not own polling timers or launch additional processes.

## Components

- `DesktopWidgetPolicy` / `DesktopWidgetKind` in MonitorCore describe selections, allowed sizes and required metrics. `MenuChartPolicy` resolves the four chart palettes and relative traffic intensity; these policies have unit tests.
- `WidgetPreferences` bridges the existing global switch and independent `widgetEnabled.compute`, `.memory`, `.network`, `.summary` choices. Missing choices retain the original three panels when the legacy global switch is enabled. Summary is off by default. Enabling an individual panel while the master switch is off enables just that panel; the master switch can pause/resume a selected group. Disabling an already-off panel while paused never resumes the group.
- `DesktopWidgetService` reconciles the selected set against its native NSPanel instances. It closes only disabled panels and retains unrelated windows, positions, sizes and movement locks. Summary supports Medium and Large only.
- `DesktopHUD` switches between specialized content. CPU/GPU never contains disk/network blocks; memory/storage never contains CPU/network blocks; network has separate incoming/outgoing graphs and identity/session details. Summary is the only mixed panel.
- `MonitorModel` unions selected widget metrics with menu readouts. A network-only panel plus a CPU menu requests CPU and network, without SMC, GPU, RAM, storage or process enumeration. Large CPU/GPU additionally requests OS CPU power-limit telemetry. Network identity refreshes reuse DiagnosticsModel.

The shared HUD history holds at most 20 three-second buckets in a rolling minute. Multiple polls in one bucket replace its current point. The larger plots use real timestamps over a 60-second domain; small/medium panels use the recent subset. Download and upload have distinct series. Missing values break the path.

## Available information

CPU frequency is explicitly **nominal**, obtained once from `hw.cpufrequency`, never presented as an instantaneous clock. Where macOS does not expose it, the value is unavailable. The throttling indicator combines the OS processor-speed limit with thermal pressure; an unavailable limit is not treated as proof of no throttling. Temperature/SMART/SSD-life/TBW values use the existing services and may be absent on unsupported hardware or adapters. Public IP reuses the user's opt-in IP service and configured refresh interval; enabling a widget does not silently enable external IP requests.

Memory totals and breakdown use binary memory amounts consistently; small sub-GB values retain adaptive units. File/network byte formatting retains its existing decimal convention.

## Menu charts

- Accent: both CPU and network use the selected accent.
- Category: CPU cyan; network green.
- Dynamic: both use green/orange/red bands below 50%, at 50–80%, above 80%. CPU uses utilization. Network uses combined current traffic relative to the highest of the last 12 readings, with a 1 MiB/s reference floor. This is relative activity, **not** a claim about link saturation.
- Monochrome: both use the system primary foreground, respecting appearance.

The full chart/text label remains one cached original NSImage so MenuBarExtra cannot drop a sibling image or squeeze out the text. Both chart colors are included in the cache key.

`bash scripts/check-optimization.sh --ui-only` checks selection, window retention, all eleven supported kind/size layouts, top-left-preserving resizing, the summary size restriction, bounded history, scroll restoration and the rendered palette in both chart regions. Captures remain private in ignored `.build/`.
