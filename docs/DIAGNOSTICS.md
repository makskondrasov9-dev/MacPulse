# MacPulse 0.9.0 diagnostics

## Architecture

- `MonitorCore/Diagnostics/BenchmarkEngine.swift` runs disk, Accelerate CPU and Metal GPU workloads away from the main actor. `DiagnosticsModel` permits one benchmark at a time, forwards cancellation, collects temperature/power-limit samples and exposes results to `DiagnosticsView`.
- `NetworkDiagnosticsService` owns the asynchronous `Process` for `/usr/bin/networkQuality -c`. It parses JSON bit/s into decimal Mbps. Idle latency is milliseconds; RPM is responsiveness, **not ICMP ping**. Missing fields remain unavailable. A nonzero exit or malformed result is an error.
- `NetworkIdentity.current()` uses `getifaddrs` for up, non-loopback Ethernet/Wi-Fi/VPN/bridge IP interfaces, including IPv6. It reads current link-layer MAC addresses when exposed, with SystemConfiguration metadata as a fallback. The detailed list includes connected interfaces, not a claim that every listed interface is the default route. The normal view excludes link-local/loopback/unspecified addresses and empty interfaces; a switch restores the technical view. Missing MAC and other unavailable values are hidden by default. Local IP prefers the system primary physical interface. VPN indication requires a tunnel with a usable assigned address, not just a utun name; it does not claim traffic protection. These summaries are shared by Monitor and menu-bar settings (local/public IP selection).
- `IPHistory` keeps at most 200 changes, persisted by `AnalyticsStore` in `~/Library/Application Support/MacPulse/Analytics/`. Local changes are sampled every 15 seconds. Public IP queries are **off by default**; enabling them sends an HTTPS request to `api64.ipify.org` no more frequently than once per minute (or on explicit refresh). Network transitions invalidate the old public IP. The ledger contains observations, not a complete packet-level VPN audit.
- `InsightsModel` reuses the existing monitor poll. Session peaks include valid CPU temperature, RAM bytes and the highest available GPU load across devices. `DailyUsage` stores approximate foreground time, opt-in, without window titles. Poll gaps/sleep are excluded, and idle checks stop accumulation after 60 seconds. Daily totals reset at local midnight; the first poll across midnight is split at the boundary. CPU-consumer rankings integrate sampled CPU percentages into CPU-seconds, **not energy usage**.

## Disk test

A private file is created with `O_EXCL | O_NOFOLLOW`, mode 0600, in the user's temporary directory. It is unlinked immediately while the descriptor remains open, so cancellation, process exit and failures leave no pathname behind. It tests **that volume**, not an arbitrary external drive.

The normal payload is 1,000,000,000 bytes. The engine requires an extra 512 MB free, sets `fcntl(fd, F_NOCACHE, 1)`, writes randomized 4 MiB buffers sequentially, performs `F_FULLFSYNC`, seeks to zero and reads sequentially. Partial I/O and interruptions are handled. Write timing includes the flush. Results use decimal MB/s. OS caching is bypassed; SSD controller caches, APFS, adapters and other workloads still affect measurements. This is not a direct measurement of raw NAND performance.

Cancellation is checked between chunks. A kernel I/O or flush already in progress must return before cancellation completes; the UI remains asynchronous throughout.

## Stress and display tests

CPU durations are 15/30/60 seconds, with one Accelerate vector worker per logical processor. GPU testing submits short Metal compute batches to the default Metal device and drains a submitted command before returning on cancellation. Batches/second describes this workload, not a standardized cross-machine performance score. Both engines stop at critical system thermal state.

The UI graphs available CPU/GPU temperatures and uses `IOPMCopyCPUPowerStatus` speed-limit percentages plus `ProcessInfo.thermalState` as throttling indicators. They are **not a measured clock frequency** or proof that no throttling occurred between samples. Unavailable sensors remain blank.

The display inspector uses the current display’s native color profile to keep the panel RGB channels pure on wide-gamut screens. It opens a borderless window on the current screen, hides the cursor and cycles red/green/blue/white/black with a click or Space. Escape closes it and restores the cursor. It is a visual inspection tool, not automatic pixel-defect detection.

## Validation

```sh
bash scripts/swift-local.sh build
bash scripts/swift-local.sh test
python3 scripts/check-localizations.py
# Explicitly opt in to 1 GB disk write, 15 s CPU stress and external network traffic:
MACPULSE_RUN_DIAGNOSTICS=1 bash scripts/swift-local.sh test --filter actualHardwareBenchmarks
```

Default tests use a small temporary disk fixture and local subprocesses, not internet bandwidth or a full stress run. They cover JSON units/missing data, invalid IPs, history deduplication/retention, cancellation, subprocess timeout, midnight/sleep accounting, persistence and peak validation.

Local validation on 13 October 2026 (Intel iMac, Sonoma): the 85-test suite passed (80 default tests; five hardware opt-ins skipped in that run). The three new hardware opt-ins and the existing live-collector test were then run separately and passed; the privileged fan-write test was not rerun because fan control was unchanged. The 1 GB test measured approximately 448 MB/s write and 429 MB/s read; networkQuality measured 60.2/42.9 Mbps and 95 RPM. These are one machine's observations, not product performance guarantees. CPU and GPU runs each completed 15 seconds; GPU cancellation and a live ipify response were also checked.

`bash scripts/check-display-test.sh` briefly opens the display inspector, verifies all five rendered channel values and click/Space/Escape handling, then closes it. This interactive check passed on the iMac. It requires a logged-in graphical session and is intentionally not part of unattended CI.

The GitHub workflow includes a native arm64 macOS test job as well as Intel tests and Universal packaging. A virtualized ARM runner does not replace physical Apple Silicon sensor and display validation.

Remaining manual checks before release: cancel each test, switch away/back while it runs, quit during a test, cycle all display colors and exit with Escape, compare VPN/local-IP transitions, verify no numeric temperatures appear on unsupported hardware, and check all 12 languages on narrow windows. macOS 13 remains the deployment target; compilation is not a substitute for a Ventura runtime test.

Sources: [Apple thermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property), the macOS SDK `IOPMLib.h` and local `networkQuality -h`, [ipify endpoint documentation](https://www.ipify.org/).
