# Homebrew Cask formula for Reader-Mac (unsigned).
# After tagging a GitHub release with the DMG attached, fill in `version`,
# `sha256`, and the `url`, then submit a PR to homebrew-cask OR host this
# file in your own tap (e.g. github.com/WeirdoMeng/homebrew-tap).
#
# Users install with:
#   brew tap WeirdoMeng/tap
#   brew install --cask reader-mac
#
# `brew install --cask` automatically strips com.apple.quarantine xattr,
# so users won't see the "unidentified developer" Gatekeeper prompt.

cask "reader-mac" do
  version "0.1.0"
  sha256 "REPLACE_WITH_REAL_SHA256"

  url "https://github.com/WeirdoMeng/Reader-Mac/releases/download/v#{version}/Reader-Mac-#{version}.dmg"
  name "Reader-Mac"
  desc "Lightweight novel reader for macOS (port of binbyu/Reader)"
  homepage "https://github.com/WeirdoMeng/Reader-Mac"

  app "ReaderMac.app"

  zap trash: [
    "~/Library/Preferences/com.weirdomeng.ReaderMac.plist",
  ]
end
