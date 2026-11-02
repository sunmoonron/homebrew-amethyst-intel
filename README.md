# Amethyst for Intel Macs

[Amethyst](https://github.com/vitorpamplona/amethyst) is a Nostr client by Vitor Pamplona. Its macOS download is Apple Silicon only: the project's release pipeline has no Intel Mac to build on, and `jpackage` cannot cross-compile. The source itself builds and runs fine on Intel. This repository builds it, from the unmodified upstream source at each release tag, and publishes the DMG.

Current: see the [latest release](https://github.com/sunmoonron/homebrew-amethyst-intel/releases/latest).

## Install

Pick one.

**Download the DMG.** Get `amethyst-desktop-<version>-macos-x64.dmg` from the [latest release](https://github.com/sunmoonron/homebrew-amethyst-intel/releases/latest), open it and drag Amethyst into Applications. On the first launch macOS says it cannot verify the app, because this build is not signed or notarized. Click Done, open System Settings > Privacy & Security, scroll down to the Amethyst message and click Open Anyway, then open Amethyst again. That is a one-time step. The Terminal equivalent:

```
xattr -dr com.apple.quarantine /Applications/Amethyst.app
```

**Homebrew.** Three commands: Homebrew 7 asks you to trust a tap that is not one of its own before it installs anything from it.

```
brew tap sunmoonron/amethyst-intel
brew trust sunmoonron/amethyst-intel
brew install --cask sunmoonron/amethyst-intel/amethyst-nostr
```

Then the same one-time Gatekeeper step as for the DMG (Homebrew keeps the quarantine flag; the Terminal line above clears it). The cask has the same name as the official one, so when Amethyst itself says an update is available and suggests `brew upgrade --cask amethyst-nostr`, that command does the right thing.

**Build it yourself.** On any Intel Mac with the Xcode Command Line Tools (`xcode-select --install`):

```
curl -fsSLO https://raw.githubusercontent.com/sunmoonron/homebrew-amethyst-intel/main/build.sh
bash build.sh --install
```

It builds the latest upstream release by default; `--tag v1.21.0` picks a specific one, and `--install` copies the finished app into /Applications. The script puts a Temurin JDK 21 in `~/.jdks` and an empty Android SDK folder in `~/Library/Android/sdk`, and clones and builds in `~/amethyst-intel-build`. Nothing lands outside your home folder. The first build takes 20 to 40 minutes. Read the script before running it; it is short.

## Updates

- Homebrew: `brew upgrade --cask amethyst-nostr`.
- DMG: on GitHub, Watch > Custom > Releases on this repository, then download the new DMG when it arrives.
- Built it yourself: run `build.sh` again.

New upstream releases show up here on their own. A [workflow](.github/workflows/build-intel-dmg.yml) checks upstream every six hours and, when there is a release this repository has not built, builds the tag on GitHub's `macos-15-intel` runner, publishes the release here and bumps the cask. If it has not caught up with a fresh upstream release yet, `build.sh` will.

Amethyst's own update check stays quiet on Intel for now. The app looks at upstream's releases for a file for the platform it runs on, and upstream publishes none for Intel. The day upstream ships an `amethyst-desktop-<version>-macos-x64.dmg`, that same check will offer it, you can move to the official build, and this repository will stop.

## What is changed

One thing. Upstream's build compiles a small macOS video-player shim (`desktopApp/native/macos-video-player`) with a hardcoded `-arch arm64`, whatever CPU runs the build, so an Intel package would carry a dylib it cannot load and video would fall back to the library's own player, which crashes in its audio tap. `build.sh` patches that one task to build the shim for the CPU it runs on. The patch is in [patches/](patches/), is proposed upstream, and is skipped automatically once a checkout no longer needs it.

Everything else is upstream's own release task, `./gradlew :desktopApp:packageReleaseDmg`, run on an x86_64 machine with JDK 21, which is exactly what upstream's CI does for Apple Silicon. Each release's notes name the upstream tag, the workflow run that built it and the DMG's sha256.

Differences from the official Apple Silicon build:

- Unsigned and not notarized: there is no Apple Developer certificate here. Hence the one-time Gatekeeper step.
- The Chromium that upstream bundles for napplets (JCEF) is downloaded on first use, as upstream does it; it has x86_64 builds.

Checked on Intel: login, feeds, notifications, images, live streams. One library in the bundle, androidx `sqlite-bundled`, ships no Intel macOS native, but the desktop app never opens the store that uses it (upstream's `amy` CLI and `geode` relay do, which is why those stay Apple Silicon only).

## Upstream

The proper fix is one leg in upstream's release workflow plus the shim fix above. GitHub offers `macos-15-intel` and `macos-26-intel` runners, and the app's updater already understands a `macos-x64.dmg` asset, so an upstream Intel DMG would update itself like every other platform. Upstream dropped its Intel leg in May 2026 when the old `macos-13` runner retired; the replacement runners arrived later. The proposal is on [this branch](https://github.com/sunmoonron/amethyst/tree/feat/ci-macos-intel-dmg); this repository exists until it lands.

## License

The files here are MIT. Amethyst itself is MIT, copyright Vitor Pamplona and contributors.
