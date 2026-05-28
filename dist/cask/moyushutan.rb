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
  sha256 "4505b73b23cb4c7b9df993ea9b448d873b5c6f8a6025690ce844c2f5eb616dc9"

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
