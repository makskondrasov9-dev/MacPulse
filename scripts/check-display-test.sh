#!/bin/bash
# Interactive smoke test: briefly fills the current screen with five test colors.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
EXTRA=()
if [[ -f .build/toolchain/overlay.json ]]; then
    EXTRA=(-vfsoverlay .build/toolchain/overlay.json -module-cache-path .build/toolchain/cache)
fi
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macosx13.0" "${EXTRA[@]}" \
    Sources/iMacMonitor/Views/DisplayTestController.swift scripts/diagnostics/DisplaySmoke.swift -o .build/DisplaySmoke
.build/DisplaySmoke
