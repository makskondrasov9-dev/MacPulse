# MacPulse

A native menu bar monitor and disk cleaner for macOS 14 or later. One app for Intel and Apple Silicon, with 12 interface languages.

[Download MacPulse.dmg](https://github.com/makskondrasov9-dev/MacPulse/releases/latest/download/MacPulse.dmg) · [Release notes](https://github.com/makskondrasov9-dev/MacPulse/releases) · [Русский](README.md)

## Install

Open the DMG, drag MacPulse into Applications, then launch it. Click the CPU indicator in the menu bar to open the dashboard. To update, quit the running app before replacing it. Your preferences are preserved.

The app is not yet signed with Developer ID or notarized by Apple. If macOS blocks it, try opening it, then use **System Settings → Privacy & Security → Open Anyway**, only if you trust the download. [Apple's instructions](https://support.apple.com/102445). No Terminal commands or disabling security are required.

## Features

- CPU, RAM, GPU/VRAM, storage, temperature and activity history; battery information appears on supported laptops.
- Configurable menu bar indicators, refresh interval, and system/light/dark appearance.
- Select a process to view details and request termination, or use the larger button in the table. Confirmation is required and critical processes are protected. Unsaved changes may be lost; macOS can refuse termination.
- Fan controls on supported Intel Macs: automatic mode, minimum speed or a temperature curve. macOS can still raise fan speeds. On Apple Silicon, fan readings are read-only where available. The tab is hidden when no sensors are found.
- Quick Clean and manual cleanup with a preview. **Quick Clean permanently empties accessible Trash items.** Browser profiles and logins are preserved in safe mode; deep cleanup requires a separate selection and confirmation. Full Disk Access is optional.

In **Settings → Application language**, choose English, Russian, Spanish, French, German, Brazilian Portuguese, Italian, Simplified Chinese, Japanese, Korean, Arabic or Hindi. **Follow system** selects a supported system language, with English as the fallback. Changes apply immediately. Process names, file paths and system-owned authorization dialogs keep their original language.

MacPulse runs locally, without an account, ads, telemetry or runtime translation requests.

## Fan control details

Custom control requires administrator authorization through macOS. No permanent service is installed. A session helper restores original minimum speeds on quit, sleep or loss of connection. Do not run other fan controllers at the same time. Force-killing the helper itself can leave an elevated minimum until a restart; macOS can still increase speeds for cooling.

## Development

See [development instructions](docs/DEVELOPMENT.md) for SwiftPM builds, tests and packaging. Translations are committed JSON resources. Translation corrections and bug reports are welcome.

[MIT License](LICENSE).
