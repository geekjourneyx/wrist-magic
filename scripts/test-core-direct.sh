#!/usr/bin/env bash
# Linux-only fallback when SwiftPM's Process probe fails in a managed container.
# Normal macOS CI continues to use test-core.sh / SwiftPM.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
python3 - "$work" <<'PY'
import pathlib, re, sys
root = pathlib.Path('Packages/WristMagicCore/Tests/WristMagicCoreTests')
entries = []
lines = ['import XCTest']
for path in sorted(root.glob('*.swift')):
    source = path.read_text()
    classes = re.findall(r'final class (\w+)\s*:\s*XCTestCase', source)
    if len(classes) != 1:
        raise SystemExit(f'{path}: direct runner requires one XCTestCase class')
    name = classes[0]
    methods = re.findall(r'func (test\w+)\(\)', source)
    if not methods or re.search(r'func test\w+\(\)\s*(?:async|throws)', source):
        raise SystemExit(f'{path}: add explicit async/throwing support before using direct runner')
    pairs = ','.join(f'("{method}", {method})' for method in methods)
    lines.append(f'extension {name} {{ static let allTests = [{pairs}] }}')
    entries.append(f'testCase({name}.allTests)')
lines.append('XCTMain([' + ','.join(entries) + '])')
pathlib.Path(sys.argv[1], 'main.swift').write_text('\n'.join(lines))
PY
mapfile -t sources < <(rg --files Packages/WristMagicCore/Sources -g '*.swift' | sort)
mapfile -t tests < <(rg --files Packages/WristMagicCore/Tests -g '*.swift' | sort)
# Domain compiles with production Swift 6 strict concurrency. XCTest legacy
# discovery glue compiles in Swift 5 mode, as it holds non-Sendable test methods.
SWIFT_USE_OLD_DRIVER=1 swiftc -swift-version 6 -emit-library -emit-module -enable-testing \
  -module-name WristMagicCore -o "$work/libWristMagicCore.so" \
  -emit-module-path "$work/WristMagicCore.swiftmodule" "${sources[@]}"
SWIFT_USE_OLD_DRIVER=1 swiftc -swift-version 6 -typecheck -I "$work" "${tests[@]}"
SWIFT_USE_OLD_DRIVER=1 swiftc -swift-version 5 -I "$work" -L "$work" -lWristMagicCore \
  "${tests[@]}" "$work/main.swift" -o "$work/tests"
LD_LIBRARY_PATH="$work:${LD_LIBRARY_PATH:-}" "$work/tests"
