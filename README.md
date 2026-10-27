# dev-setup

レンタルPC など、まっさらな Windows / Mac に GitHub のプロジェクトを動かす環境を 1 回で用意し、返すときに 1 回で片付けるためのスクリプト。

## 使い方

### Windows（PowerShell に貼る）
```powershell
$env:DEV_SETUP_REPO = 'DaiKi-Ito-110/tsuchino_himitsu'; irm https://raw.githubusercontent.com/DaiKi-Ito-110/dev-setup/main/get.ps1 | iex
```
このリポジトリを `~/.dev-setup/dev-setup-main` に取ってきて `setup.ps1` を動かす。USB などで持っていくなら `setup.bat` をダブルクリック（リポジトリを聞かれる）か `setup.bat owner/repo`。

### Mac（ターミナルに貼る）
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/DaiKi-Ito-110/dev-setup/main/setup.sh)" _ DaiKi-Ito-110/tsuchino_himitsu
```
手元にあるなら `setup.command` をダブルクリック。

### 返すとき
- Windows: `~/.dev-setup/dev-setup-main/cleanup.bat` をダブルクリック
- Mac: `bash -c "$(curl -fsSL https://raw.githubusercontent.com/DaiKi-Ito-110/dev-setup/main/cleanup.sh)"`

`-DryRun`（Mac は `--dry-run`）を付けると、何もせずに何をするかだけ出す。

## setup がすること
何度流しても安全（入っているもの・済んでいるものは飛ばす）。途中で失敗したら、直してもう一度流せば続きから。

1. Git（+ LFS）と GitHub CLI を入れる（Windows は winget、Mac は Homebrew。Mac は jq も）
2. `gh auth login --web` で GitHub にブラウザでログインし、git も HTTPS でその認証を使うようにする（SSH 鍵は置かない）。git の名前・メールが空なら聞く
3. プロジェクトを `~/dev/<repo名>` に clone（`-Dir` / `--dir` で変更）
4. Node を入れる。nodejs.org の公式 zip / tarball を `~/.dev-setup/node` に展開するので、管理者権限が要らず、メジャーを指定でき、消すのも簡単
5. `package.json` の `packageManager`（無ければロックファイル）から pnpm / yarn を入れる
6. `setup.json` の `repos` を clone し、依存を入れる（`pnpm install` など）
7. `setup.json` の `notes`（手作業でやること）を出して、フォルダを開く

入れたもの・clone したもの・足した PATH は `~/.dev-setup/*.txt` に記録する。

## cleanup がすること
1. `gh auth logout`、git の資格情報（Windows の資格情報マネージャー / Mac のキーチェーン）、gh の credential helper、setup が設定した git の名前・メールを消す
2. clone したフォルダを一覧にして（未コミット・未 push があれば警告）、確認してから消す
3. pnpm / npm / yarn のキャッシュを消す
4. setup が足した PATH（Mac は `~/.zprofile` の `# dev-setup` の行）と Node を消す
5. setup が入れたツールは聞いてからアンインストール
6. `~/.dev-setup` を消す

setup の記録が無い PC で流すと最初に確認する（自分の PC で流すと普段のログイン情報やキャッシュも消えるため）。ブラウザのログインは各自でログアウトする。

## プロジェクト側に置く `setup.json`（無くても動く）
リポジトリの直下に置く。全部の項目が省略できる。

```json
{
  "node": "24",
  "repos": [
    { "repo": "owner/data-repo", "dir": "../data-repo", "lfs": true, "optional": true, "why": "データを作り直すときだけ要る" }
  ],
  "install": "pnpm install",
  "postInstall": ["node scripts/prepare.mjs"],
  "notes": ["起動は start.bat（Mac は start.command）"]
}
```

| 項目 | 意味 | 省略したとき |
|---|---|---|
| `node` | Node のメジャー（`"lts"` も可） | `.nvmrc` → `.node-version` → `package.json` の `engines.node` → `package.json` があれば LTS |
| `repos` | 一緒に clone するリポジトリ。`dir` はプロジェクトからの相対、`lfs` で `git lfs pull`、`optional` なら clone するか聞く | なし |
| `install` | 依存を入れるコマンド | `packageManager` / ロックファイルから（`pnpm install`、`npm ci` など） |
| `postInstall` | install の後に流すコマンド | なし |
| `notes` | 最後に出す「手作業でやること」 | `start.bat` / `start.command` があればその案内 |

## 前提
- Windows 10 / 11（winget が要る。無ければ Microsoft Store の「アプリ インストーラー」）。winget のインストールで管理者の確認が出ることがある
- macOS（Homebrew の導入で Mac のパスワードを聞かれる）
- 別の Node が先に PATH にあると setup が警告する（そのときはアンインストールか PATH の順番を直す）
