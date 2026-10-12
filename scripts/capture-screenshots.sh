#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/swift-local.sh build
BIN="$(bash scripts/swift-local.sh build --show-bin-path)"
mkdir -p .build/screenshots docs/screenshots
# Keep screenshot-only navigation out of the shipping executable.
python3 - <<'PY'
from pathlib import Path
source = Path('Sources/iMacMonitor/Views/MainWindowView.swift').read_text()
needle = '.frame(minWidth: 680, minHeight: 500)'
assert source.count(needle) == 1
source = source.replace(needle, needle + '''
        .onReceive(NotificationCenter.default.publisher(for: .init("MacPulseScreenshotSection"))) { notification in
            if let section = notification.object as? String { selection = MainSection(rawValue: section) }
        }''')
Path('.build/screenshots/MainWindowView.swift').write_text(source)
PY
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find Sources/iMacMonitor -name '*.swift' ! -name iMacMonitorApp.swift ! -name MainWindowView.swift)
EXTRA=()
if [[ -f .build/toolchain/overlay.json ]]; then
    EXTRA=(-vfsoverlay .build/toolchain/overlay.json -module-cache-path .build/toolchain/cache)
fi
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macosx13.0" "${EXTRA[@]}" \
    -I "$BIN/Modules" -Xcc -fmodule-map-file="$BIN/CSystem.build/module.modulemap" -I Sources/CSystem/include \
    "${SOURCES[@]}" .build/screenshots/MainWindowView.swift scripts/screenshots/CaptureApp.swift \
    "$BIN"/MonitorCore.build/*.swift.o "$BIN"/CSystem.build/*.o -framework IOKit -o .build/screenshots/MacPulseScreenshots
.build/screenshots/MacPulseScreenshots
