#!/bin/bash
# =============================================================================
# Scripts/probe-codex-ratelimits.sh
#
# TokenChecker が Codex から受け取っているのと同じ生データを表示する。
#   1. `codex app-server` を stdio で起動
#   2. initialize → initialized → account/rateLimits/read を送る
#   3. id:2 の応答（rateLimits / rateLimitsByLimitId）を整形して出力
#
# 「Codex セクションにモデル別の枠（GPT-x など）が出るはず／出ない」を切り分けるときに使う。
# Claude Code のサンドボックス内では chatgpt.com への通信が遮断されるため、
# ターミナル.app から実行すること。
#
# 使い方:
#   bash Scripts/probe-codex-ratelimits.sh                 # アプリと同じ codex を使う
#   bash Scripts/probe-codex-ratelimits.sh /path/to/codex  # 任意のバイナリを指定
# =============================================================================
set -uo pipefail

BIN="${1:-}"
if [[ -z "${BIN}" ]]; then
    # アプリの設定 (defaults codexPath) → PATH 上の codex の順で探す
    BIN="$(defaults read com.token-checker.app codexPath 2>/dev/null || true)"
    [[ -x "${BIN}" ]] || BIN="$(command -v codex || true)"
fi
if [[ ! -x "${BIN}" ]]; then
    echo "codex 実行ファイルが見つかりません。引数でパスを指定してください。" >&2
    exit 1
fi

echo "codex: ${BIN}"
echo "version: $("${BIN}" --version 2>/dev/null)"
echo "----- account/rateLimits/read -----"

(
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"tokenchecker-probe","version":"0.0.1"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"initialized","params":{}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}'
    sleep 10
) | "${BIN}" app-server 2>/dev/null \
  | python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        msg = json.loads(line)
    except json.JSONDecodeError:
        continue
    if msg.get("id") == 2:
        print(json.dumps(msg, ensure_ascii=False, indent=2))
        break
else:
    print("id:2 の応答が届きませんでした（タイムアウトか、app-server の起動方法が変わった可能性）")
'
