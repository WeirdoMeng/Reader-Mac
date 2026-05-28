# Homebrew Cask formula for 摸鱼书摊（未签名）
# After tagging a GitHub release with the DMG attached, fill in `version`,
# `sha256`, and the `url`, then submit a PR to homebrew-cask OR host this
# file in your own tap (e.g. github.com/WeirdoMeng/homebrew-tap).
#
# Users install with:
#   brew tap WeirdoMeng/tap
#   brew install --cask moyushutan
#
# `brew install --cask` automatically strips com.apple.quarantine xattr,
# so users won't see the "unidentified developer" Gatekeeper prompt.

cask "moyushutan" do
  version "0.2.0"
  sha256 "884d467e10ee3b74e6ae2855985154a72887db30da21be9f2fbcc9b91b85b79e"

  url "https://github.com/WeirdoMeng/Reader-Mac/releases/download/v#{version}/MoyuShutan-#{version}.dmg"
  name "摸鱼书摊"
  desc "原生 macOS 小说阅读器"
  homepage "https://github.com/WeirdoMeng/Reader-Mac"

  app "摸鱼书摊.app"

  zap trash: [
    "~/Library/Preferences/com.weirdomeng.MoyuShutan.plist",
    "~/Library/Application Support/MoyuShutan",
  ]
end
