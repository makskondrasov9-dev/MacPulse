# Screenshot capture

Run `bash scripts/capture-screenshots.sh` from an interactive macOS desktop session.
The separate capture executable uses the shipping SwiftUI views, an isolated preferences domain, real metrics and the installed-app list. It samples for 26 seconds, navigates the four sections and captures its own menu-bar item. It never invokes cleanup, app removal, process termination or custom fan control. The capture-specific navigation hook is generated under ignored `.build/`, not shipped in MacPulse.

The script first invokes `/usr/sbin/screencapture -x -o -l<window_id>`. The menu-bar item uses its exact on-screen rectangle (`-R`) to retain the real menu-bar background. If that tool cannot capture the window, it tries the process's own window through the macOS window-image API. Screen Recording permissions and a visible desktop session may be required. Do not publish captures containing personal paths or content without reviewing them.

The images in this directory were captured on an Intel iMac 2017 running Sonoma. They are real UI captures, not mockups or evidence of runtime testing on Ventura or Apple Silicon. Background workloads affect readings.
