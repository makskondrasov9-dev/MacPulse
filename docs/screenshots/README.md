# Screenshot capture

Run `bash scripts/capture-screenshots.sh` from an interactive macOS desktop session.
The separate capture executable uses the shipping SwiftUI views, an isolated preferences domain, real metrics and the installed-app list. It samples for 26 seconds, navigates the four sections and captures its own menu-bar item. It never invokes cleanup, app removal, process termination or custom fan control. The capture-specific navigation hook is generated under ignored `.build/`, not shipped in MacPulse.

The script first invokes `/usr/sbin/screencapture -x -o -l<window_id>`. The menu-bar item uses its exact on-screen rectangle (`-R`) to retain the real menu-bar background. If that tool cannot capture the window, it tries the process's own window through the macOS window-image API. Screen Recording permissions and a visible desktop session may be required. Do not publish captures containing personal paths or content without reviewing them.

The images in this directory were captured on an Intel iMac 2017 running Sonoma. They are real UI captures, not mockups or evidence of runtime testing on Ventura or Apple Silicon. Background workloads affect readings.


For the 1.0.1 changes, run `bash scripts/capture-screenshots.sh --updates-only`. It opens the real Settings views with live metrics and captures General, Menu Bar and Widgets. This mode leaves IP/VPN readouts and public-IP lookup off and omits the Network/IP history tab from public captures. The widget gallery uses the real panels captured by `bash scripts/check-optimization.sh --ui-only`; the published images omit the large network panel because it contains local addresses. No screenshot navigation hook is added to the shipped executable.
