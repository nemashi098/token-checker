# TokenChecker Notes

このフォルダーは、TokenChecker の引き継ぎメモや調査メモを置く場所です。


## 2026-09-05 現行バージョンとの整合確認＋公式ロゴ化

### 確認したこと（Claude Code 2.1.261 / Codex CLI 0.148.0・ChatGPT.app 内蔵 0.153.0-alpha.5）
- 上流 `otoha1119/token-checker` の main は 2026-05-30 の b06c286 のまま（新コミットなし）
- Codex: `codex app-server generate-json-schema` で出した `GetAccountRateLimitsResponse` /
  `RateLimitSnapshot` / `RateLimitWindow` は `CodexRateLimitsDTO` と一致（`rateLimitsByLimitId`・
  `limitName`・`usedPercent`・`windowDurationMins`・`resetsAt`）。引数なしの `codex app-server`
  も両バージョンで initialize が通る。なお `app-server daemon start` は「managed standalone
  install」が無いこの Mac では動かない（app 側は app-server 直起動を先に試すので影響なし）
- アプリが使う codex は `defaults codexPath` = ChatGPT.app 内蔵バイナリ
- Claude: `/api/oauth/usage` は 200。`limits[]` の weekly_scoped（display_name "Fable"）は
  既存の scopedWeekly 経路で表示される。`spend` / `extra_usage`（追加クレジット）は未表示
- Codex のモデル別枠（GPT-x）が出るかは**バックエンド次第**（8〜9月のセッションログでは
  limit_id "codex" 単独・limit_name null）。実データは `Scripts/probe-codex-ratelimits.sh` で確認

### 変更
- 公式ロゴ化: `Resources/claude-mark.svg`（simple-icons の Claude マーク・約 2 KB・template）、
  `Resources/codex-logo.png`（ChatGPT.app の app.asar 内 `codex-app-ga-logo` 104px 透過・約 10 KB）
- `Utilities/BrandAssets.swift` で読み込み。失敗時は従来の手描き図形へフォールバック
- `DonutCenter.image` を追加しメニューバーのドーナツ中央も公式ロゴに
- ブランド色: Claude #D97757、Codex は公式ロゴの青紫へ
- テスト: `BrandAssetsTests`（読み込み可否・サイズ上限 8 KB / 32 KB）
- リセット権の表示（同日追加）: `rateLimitResetCredits` を DTO に追加し、`ServiceUsage.resetCredits`
  （枚数＋最短失効日）として Codex セクション末尾に 1 行表示。失効 7 日以内は橙。旧 CLI で
  フィールドが無い／0 枚なら行ごと非表示。テスト `CodexResetCreditsTests`（6 件）
- 「使う」ボタン（同日追加）: `account/rateLimitResetCredit/consume`（idempotencyKey=UUID・creditId 省略）
  を `CodexAppServerClient.consumeResetCredit` で呼ぶ。`ResetCreditRedeemer` プロトコルを
  CodexUsageProvider だけが実装し、ViewModel は `as?` で能力判定。押下時は NSAlert で確認→
  実行→結果を outcome 4 値で表示→使用量を再取得。結果行はカードが消えても残る（× で閉じる）
