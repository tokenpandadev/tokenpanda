# The cask for the tap repository tokenpandadev/homebrew-tap, copied there as Casks/tokenpanda.rb.
# RELEASE_VERSION and RELEASE_SHA256 are set by the release: the version of scripts/build-app.sh
# and the SHA-256 it prints for build/tokenpanda-<version>.zip.
cask "tokenpanda" do
  version "RELEASE_VERSION"
  sha256 "RELEASE_SHA256"

  url "https://github.com/tokenpandadev/tokenpanda/releases/download/v#{version}/tokenpanda-#{version}.zip"
  name "tokenpanda"
  desc "Menu bar pace for Claude Code plan windows, and the Mac's own figures"
  homepage "https://tokenpanda.dev"

  depends_on macos: ">= :sonoma"

  app "tokenpanda.app"

  uninstall quit: "dev.tokenpanda.app"

  zap trash: [
    "~/Library/Application Support/dev.tokenpanda.app",
    "~/Library/Preferences/dev.tokenpanda.app.plist",
  ]

  caveats <<~EOS
    The app is signed ad hoc, not notarised. On first launch macOS blocks it:
    open System Settings, Privacy & Security, and click Open Anyway.

    Before you uninstall, open tokenpanda's Settings tab and click
    "Remove the status line entry", so ~/.claude/settings.json gets its
    previous statusLine back.
  EOS
end
