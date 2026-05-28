# 发版 + Homebrew Cask 部署指南

每次出新版本，按这个流程跑：

## 0. 打 DMG（任意目录均可）

```bash
cd /Users/apple/Desktop/AppleSpace/Reader-Mac
./scripts/make_dmg.sh 0.2.0
```

产物：`dist/MoyuShutan-0.2.0.dmg` + 同步输出 `SHA256` 字符串（记下来下一步用）。

## 1. 发 GitHub Release

GitHub 网页：

1. 打开 https://github.com/WeirdoMeng/Reader-Mac/releases/new
2. Tag: `v0.2.0` （要打头加 `v`）
3. Target: `main`
4. Release title: `摸鱼书摊 v0.2.0`
5. Description: 简单写本版更新点
6. **Attach binaries**: 把本机的 `dist/MoyuShutan-0.2.0.dmg` 拖进去
7. Publish release

完成后，DMG 公开 URL = `https://github.com/WeirdoMeng/Reader-Mac/releases/download/v0.2.0/MoyuShutan-0.2.0.dmg`

> 也可以装 `gh` CLI 然后 `gh release create v0.2.0 dist/MoyuShutan-0.2.0.dmg --notes "..."` 一行搞定。

## 2. 更新 Cask 公式里的 sha256

`make_dmg.sh` 末尾输出的 SHA256 替换 `dist/cask/moyushutan.rb` 里 `sha256 "..."`。 

```ruby
sha256 "4505b73b23cb4c7b9df993ea9b448d873b5c6f8a6025690ce844c2f5eb616dc9"
```

每次重打 DMG sha256 都会变，记得同步。

## 3. 建一次 Homebrew Tap 仓库（**仅首次**）

GitHub 网页：

1. https://github.com/new
2. Repository name: **必须** `homebrew-tap`（前缀 `homebrew-` 是 brew 约定，brew tap 会自动加上）
3. Owner: `WeirdoMeng`
4. Public
5. 不要 init README（你自己来）
6. Create

本地：

```bash
cd ~/Desktop
git clone https://github.com/WeirdoMeng/homebrew-tap.git
cd homebrew-tap
mkdir -p Casks
cp /Users/apple/Desktop/AppleSpace/Reader-Mac/dist/cask/moyushutan.rb Casks/
git add -A
git commit -m "cask: moyushutan v0.2.0"
git push -u origin main   # 或 master，看你新仓库默认分支
```

之后每发新版只要更新 `Casks/moyushutan.rb` 里的 `version` 和 `sha256`，再 push 即可。

## 4. 用户怎么安装

```bash
brew tap WeirdoMeng/tap          # 仅首次，brew 自动到 github.com/WeirdoMeng/homebrew-tap
brew install --cask moyushutan
```

`brew install --cask` 会自动剥离 quarantine 属性，跳过 Gatekeeper 弹窗。

## 排错

| 现象 | 原因 | 修复 |
|---|---|---|
| `brew tap WeirdoMeng/tap` 报 not found | 你还没建仓库 | 看本文 §3 |
| `Error: SHA256 mismatch` | cask sha256 没同步 | 重算 → 改 cask → push tap |
| `Error: download failed` | Release 没上传 DMG | GitHub Release 里附 DMG |
| `App is damaged` (打开报错) | 用户没用 brew install --cask 装 | 终端 `xattr -dr com.apple.quarantine "/Applications/摸鱼书摊.app"` |

## 一图速览

```
开发完成
   ↓
make_dmg.sh 0.2.0      ──→  dist/MoyuShutan-0.2.0.dmg + sha256
   ↓
GitHub Release v0.2.0  ──→  公开下载 URL
   ↓
改 cask 的 sha256       ──→  dist/cask/moyushutan.rb 更新
   ↓
推到 homebrew-tap 仓库  ──→  brew tap 后可用
   ↓
brew install --cask moyushutan ✓
```
