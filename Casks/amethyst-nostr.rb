cask "amethyst-nostr" do
  version "1.21.0"
  sha256 "58412d7009467bcf8401bd332f879ebc7b03c2026535f778265d5bcdc7a14205"

  url "https://github.com/sunmoonron/homebrew-amethyst-intel/releases/download/v#{version}/amethyst-desktop-#{version}-macos-x64.dmg"
  name "Amethyst"
  desc "Nostr client, community build for Intel Macs"
  homepage "https://github.com/sunmoonron/homebrew-amethyst-intel"

  livecheck do
    url :url
    strategy :github_latest
  end

  conflicts_with cask: "amethyst"
  depends_on arch: :x86_64
  depends_on :macos

  app "Amethyst.app"

  zap trash: [
    "~/.amethyst",
    "~/Library/Application Support/Amethyst",
    "~/Library/Caches/AmethystDesktop",
    "~/Library/Preferences/com.vitorpamplona.amethyst.plist",
  ]

  caveats <<~EOS
    This build is not signed or notarized, so Gatekeeper blocks the first launch.
    Either open System Settings > Privacy & Security and click "Open Anyway"
    after the first attempt, or clear the quarantine flag once:
      xattr -dr com.apple.quarantine /Applications/Amethyst.app
    The upstream project signs only its Apple Silicon build.
  EOS
end
