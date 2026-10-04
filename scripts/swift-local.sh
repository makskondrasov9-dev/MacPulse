#!/bin/bash
# Work around mixed-version CLT PackageDescription interfaces without changing CLT.
set -euo pipefail
cd "$(dirname "$0")/.."
MANIFEST_COMPILER="$(python3 - <<'PY'
import json, pathlib, shlex, subprocess
compiler = pathlib.Path(subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip())
modules = compiler.parent.parent / 'lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule'
directory = pathlib.Path('.build/toolchain').resolve()
directory.mkdir(parents=True, exist_ok=True)
roots = []
legacy = compiler.parent.parent / 'include/swift/module.modulemap'
modern = legacy.with_name('bridging.modulemap')
if legacy.exists() and modern.exists() and 'module SwiftBridging' in legacy.read_text() and 'module SwiftBridging' in modern.read_text():
    empty = directory / 'empty.modulemap'
    empty.write_text('// Duplicate legacy SwiftBridging declaration hidden locally.\n')
    roots.append({'type': 'file', 'name': str(legacy), 'external-contents': str(empty)})
for private in modules.glob('*.private.swiftinterface'):
    public = private.with_name(private.name.replace('.private.swiftinterface', '.swiftinterface'))
    if not public.exists():
        continue
    version = lambda p: next((s for s in p.read_text().splitlines() if s.startswith('// swift-compiler-version:')), '')
    if version(private) != version(public):
        roots.append({'type': 'file', 'name': str(private), 'external-contents': str(public)})
if not roots:
    print(compiler)
else:
    directory = pathlib.Path('.build/toolchain').resolve()
    directory.mkdir(parents=True, exist_ok=True)
    overlay = directory / 'overlay.json'
    overlay.write_text(json.dumps({'version': 0, 'roots': roots}))
    wrapper = directory / 'swiftc-manifest'
    wrapper.write_text('#!/bin/bash\nexec ' + shlex.quote(str(compiler)) + ' "$@" -vfsoverlay ' + shlex.quote(str(overlay)) + ' -module-cache-path ' + shlex.quote(str(directory / 'cache')) + '\n')
    wrapper.chmod(0o755)
    print(wrapper)
PY
)"
export SWIFT_EXEC_MANIFEST="$MANIFEST_COMPILER"
if [[ "$MANIFEST_COMPILER" != "$(xcrun --find swiftc)" ]]; then
    subcommand="${1:-build}"
    if (( $# > 0 )); then shift; fi
    exec swift "$subcommand" -Xswiftc -vfsoverlay -Xswiftc "$PWD/.build/toolchain/overlay.json" -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/toolchain/cache" "$@"
else
    exec swift "$@"
fi
