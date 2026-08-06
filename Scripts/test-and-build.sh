#!/bin/bash
# =============================================================================
# Scripts/test-and-build.sh
#
# swift test → Scripts/build.sh を一括実行する。
#
# Command Line Tools 単体の環境では、テスト用の Testing.framework が
# CLT 内 (Library/Developer/Frameworks) にあるのに SwiftPM が検索パスへ
# 入れないため `no such module 'Testing'` になる。ここで -F / -rpath を
# 明示して補う。フル Xcode 環境ではこの補いは不要だが、付けても無害。
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
# Testing.framework が依存する lib_TestingInterop.dylib はさらに別の場所にあり、
# どちらも既定の探索パスに入っていないので rpath を両方通す。
INTEROP_LIB_DIR="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
EXTRA_FLAGS=()
if [[ -d "${FRAMEWORKS}" ]]; then
    EXTRA_FLAGS=(
        -Xswiftc -F -Xswiftc "${FRAMEWORKS}"
        -Xlinker -F -Xlinker "${FRAMEWORKS}"
        -Xlinker -rpath -Xlinker "${FRAMEWORKS}"
        -Xlinker -rpath -Xlinker "${INTEROP_LIB_DIR}"
    )
fi

echo "[test-and-build] swift test 実行中..."
swift test "${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"}"

echo "[test-and-build] テスト成功。アプリをビルドします..."
./Scripts/build.sh
