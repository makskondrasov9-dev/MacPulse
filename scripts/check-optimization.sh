#!/bin/bash
# Interactive smoke check of real SwiftUI/AppKit views. Opens a temporary window;
# does not register a login item, terminate processes or run stress tests.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/swift-local.sh build
BIN="$(bash scripts/swift-local.sh build --show-bin-path)"
mkdir -p .build/window-smoke
python3 - <<'PY'
from pathlib import Path
source = Path('Sources/iMacMonitor/iMacMonitorApp.swift').read_text()
delegate = source[source.index('@MainActor\nfinal class AppDelegate'):]
Path('.build/window-smoke/AppDelegate.swift').write_text('import AppKit\nimport MonitorCore\n' + delegate)
PY
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(rg --files Sources/iMacMonitor -g '*.swift' -g '!iMacMonitorApp.swift')
EXTRA=()
if [[ -f .build/toolchain/overlay.json ]]; then
    EXTRA=(-vfsoverlay .build/toolchain/overlay.json -module-cache-path .build/toolchain/cache)
fi
xcrun swiftc -whole-module-optimization -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macosx13.0" "${EXTRA[@]}" \
    -I "$BIN/Modules" -Xcc -fmodule-map-file="$BIN/CSystem.build/module.modulemap" -I Sources/CSystem/include \
    "${SOURCES[@]}" .build/window-smoke/AppDelegate.swift scripts/diagnostics/OptimizationSmoke.swift \
    "$BIN"/MonitorCore.build/*.swift.o "$BIN"/CSystem.build/*.o -framework IOKit -o .build/window-smoke/OptimizationSmoke
.build/window-smoke/OptimizationSmoke "$@"
