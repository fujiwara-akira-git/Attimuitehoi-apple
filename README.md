# Attimuitehoi (Apple)

このリポジトリは `Attimuitehoi` の Apple 向けソース（iOS / macOS）です。

- Swift / SwiftUI
- Xcode プロジェクト: `Attimuitehoi.xcodeproj`
- 推奨ブランチ: `main`

使い方
- Xcode で開いてビルド、またはコマンドラインでビルド:

```bash
# macOS 用ビルド (Debug)
xcodebuild -project Attimuitehoi.xcodeproj -scheme "Attimuitehoi-mac" -configuration Debug -destination 'platform=macOS' clean build

# iOS 用ビルド (Simulator)
xcodebuild -project Attimuitehoi.xcodeproj -scheme "Attimuitehoi-iOS" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 14' clean build
```

CI
- `.github/workflows/ios.yml` で macOS ビルドを実行します。

ブランチ保護
- リポジトリの `main` ブランチに保護ルールを適用するには、付属のスクリプトを使用してください: `scripts/branch_protect.sh`

スクリプト使用例

```bash
# 簡易実行（対話あり）
GITHUB_OWNER=fujiwara-akira-git GITHUB_REPO=Attimuitehoi-apple GITHUB_TOKEN=ghp_xxx ./scripts/branch_protect.sh

# 複数リポジトリを一括（対話あり）
GITHUB_OWNER=fujiwara-akira-git GITHUB_TOKEN=ghp_xxx ./scripts/branch_protect.sh -R "Attimuitehoi-apple,Attimuitehoi-web,Attimuitehoi-android"

# 事前確認をスキップして実行
GITHUB_OWNER=fujiwara-akira-git GITHUB_TOKEN=ghp_xxx ./scripts/branch_protect.sh -R "Attimuitehoi-apple" -y

# Dry-run で確認
GITHUB_OWNER=fujiwara-akira-git GITHUB_TOKEN=ghp_xxx ./scripts/branch_protect.sh -R "Attimuitehoi-web" -n
```

必要なトークン権限
- 公開リポジトリ: `public_repo` スコープで十分
- プライベートリポジトリ: `repo` スコープが必要

備考
- スクリプトは `jq` による整形出力を試みます。未インストール時は生の JSON を表示します（macOS: `brew install jq`）。

# Attimuitehoi (あっちむいてほい) iOS

このフォルダには、シンプルな SwiftUI ベースの iOS アプリ用ソースが含まれています。

使い方:

1. Xcode を開き、`App` テンプレートで新しい iOS プロジェクトを作成します（言語は Swift、UI フレームワークは SwiftUI）。
2. 作成したプロジェクト内の `ContentView.swift` と `App` ファイルを上書きするか、下記ファイルをプロジェクトに追加してください:
   - `AttimuitehoiApp.swift`
   - `ContentView.swift`
   - `GameLogic.swift` (GameLogic は `ContentView.swift` に含まれています)
3. ターゲットの iOS バージョンを iOS 15.0 以上にしてください。
4. ビルドして実行。

ゲーム説明:
- まずじゃんけんを行います（グー/チョキ/パー）。
- 勝った方が指をさす役、負けた方が首を向ける役になります。
- 指す側が左右のどちらかを選び、負けた側が同時に左右を向きます。
- 両者の方向が一致すれば指された側（首を向けた側）の負けでゲーム終了。違えば再びじゃんけんに戻ります。
