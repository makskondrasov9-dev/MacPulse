# Title

I built MacPulse: a free, open-source Mac monitor, fan controller and cleaner — no subscriptions, Intel + Apple Silicon, macOS 13+

# Post

My 2017 iMac is still useful. I wanted one native app to see what was making it work hard, check its Radeon and integrated GPU separately, manage the fan and review the files piling up on its SSD.

That became **MacPulse**, written in Swift and SwiftUI. It's MIT-licensed, with no account, telemetry, paid tier or subscription.

What it does today:

- CPU, RAM, top processes, network rates and session totals.
- Multiple GPUs, with detected VRAM capacity instead of a fixed 4 GB assumption.
- Configurable menu-bar text, tiny CPU/network sparklines, or both.
- Automatic fan mode, minimum RPM and temperature curves on supported Intel Macs.
- Cache cleanup with a manual preview, plus a one-click mode.
- An app uninstaller with drag & drop, related-file checkboxes and system-app protection.
- SMART health where the drive exposes it, laptop battery information, launch at login and 12 languages.

The new **0.8.1** build targets **macOS 13 Ventura and later**, packaged as one Intel/Apple Silicon DMG. The project started on older Intel hardware; I want it to remain useful there as well as on newer Macs.

A few honest limitations: Apple Silicon fan control is currently read-only, and some sensor readings aren't available. USB drive adapters may hide SMART. The Ventura deployment target compiles and all 69 tests pass; my local runtime testing is on Sonoma, so feedback from Ventura users would be particularly helpful. This isn't a claim that every Mac model has been tested.

Also: the app isn't Apple-notarized yet. The README explains the first-launch steps. Quick Clean permanently empties accessible Trash items alongside eligible caches and logs; choose manual cleanup if you want to inspect categories first. App removal asks for confirmation.

**Download + screenshots:** https://github.com/makskondrasov9-dev/MacPulse/releases/tag/v0.8.1

**Source, installation and limitations:** https://github.com/makskondrasov9-dev/MacPulse

I'd love feedback: which Mac and macOS version are you using, and which readings or workflows need work? Native-speaker translation fixes are welcome too. If you find it useful, a GitHub star helps people discover it.

I'm the maintainer, and this is my project.

---

Publication note (remove before posting): this is a draft for r/macapps or r/mac. Check each community's current self-promotion rules, choose the appropriate flair and avoid posting duplicate promotions in quick succession. Verify the release link is live before posting.
