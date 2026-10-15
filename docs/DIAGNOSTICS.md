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


## 0.9.0 stabilization: hardware and network lab

The CPU selector chooses 1…active logical CPU count worker tasks on Intel and Apple Silicon. macOS schedules their execution; this does **not** pin work to P/E cores. The live rate uses the existing vector workload and is sampled at approximately 1 Hz. After a three-second warm-up, its percentage is relative to the best observed rate for the same CPU model, worker count and workload version on this Mac. The best value is saved only after a completed test. This is not a theoretical model maximum or a cross-machine benchmark score.

`hw.cpufrequency`, when present, is explicitly labelled **nominal frequency**. No privileged `powermetrics` process or undocumented frequency reader is introduced, and unavailable instantaneous clocks are not fabricated. Thermal indications use system thermal state; IOPM speed limits remain separately identified as power limits that can have non-thermal causes. Missing numeric temperatures on Apple Silicon remain unavailable. Apple describes scheduler ownership of core choice in [Tune CPU job scheduling for Apple silicon games](https://developer.apple.com/videos/play/tech-talks/110147/).

The display test overlays instructions for three seconds, then returns to uninterrupted native-profile primary colors. `bash scripts/check-display-test.sh` verifies the HUD lifetime, primary pixel values and click/Space/Escape handling.

`DiagnosticProcess` executes fixed system binaries with argument arrays, no shell. It streams lines from a private unlinked output file, bounds retained output and execution time, and terminates/reaps the child on cancellation. Traceroute uses numeric output, one probe per hop, at most 20 hops and a 35-second timeout. The destination must be a hostname or literal IP, never command options. IPv6 route data comes from SystemConfiguration; a one-packet gateway probe has a five-second deadline. No ICMP reply does not prove lack of IPv6 connectivity.

The speed test fetches Apple's HTTPS configuration and passes that exact configuration to `networkQuality -C`, so the UI can list the actual configured endpoints. Live transfer rates come from the existing physical-interface counters and include other apps. A small HEAD request measures HTTP latency including connection setup, separately from the final networkQuality idle latency/RPM. This is not advertised as ICMP ping or an exact count of networkQuality's internal HTTP requests. The configuration format follows the [network-quality server specification](https://github.com/network-quality/server).

Public-IP lookup remains opt-in. Settings accept HTTPS URLs without embedded credentials or fragments and intervals from 15 to 3600 seconds, applied on the next monitor tick. Responses can be a plain IPv4/IPv6 address or JSON with an `ip` field. Body reads are capped at 1024 bytes, requests time out, cookies are disabled and redirects cannot downgrade to HTTP. Changing the URL cancels the old request; its late result cannot overwrite the new endpoint's state. History keeps interface names and up to 200 timestamped changes locally.

Validation on 14 October 2026: 91 default tests passed (97 total cases, six explicit opt-ins). The real Network Lab check separately passed on the Intel iMac: loopback traceroute, IPv6 inspection, HTTPS endpoint discovery/latency, and networkQuality (82.6 Mbps download, 67.3 Mbps upload). These speeds describe one run, not product guarantees. The display HUD/color/keyboard smoke check also passed. Physical Apple Silicon and Ventura runtime verification remain separate from Universal compilation.

The native SwiftUI smoke run also completed a 15-second CPU test with two workers, checked that live work rate, thermal samples and the measured-reference percentage arrived, then verified network endpoints/live graphs and cancellation. Local screenshots remain in ignored `.build/` and are not committed because network identity is private. Build 15 retains version 0.9.0.
