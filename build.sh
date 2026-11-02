#!/usr/bin/env bash
# build.sh - build Amethyst Desktop for Intel (x86_64) Macs from the upstream source.
#
# Upstream (github.com/vitorpamplona/amethyst) only publishes an Apple Silicon DMG
# because its release CI has no Intel Mac, and jpackage cannot cross-compile. This
# script builds the same release on an Intel Mac, with one change to upstream's build
# script (its macOS video-player shim is compiled for arm64 whatever CPU builds it;
# the fix is proposed upstream and skipped once merged). It installs nothing outside
# your home folder:
#
#   ~/.jdks/jdk-21*             Temurin JDK 21 for x64 (the build pins JDK 21)
#   ~/Library/Android/sdk       an empty Android SDK root; the shared modules have
#                               Android targets and the Android Gradle plugin wants
#                               the folder to exist, but nothing is downloaded into it
#   <work dir>/amethyst-<tag>   the upstream checkout and its build output
#   <work dir>/dist             the finished DMG and its sha256
#
# Usage: ./build.sh [--tag vX.Y.Z] [--work-dir DIR] [--install]
#
#   --tag       upstream release tag to build; default: the latest release
#   --work-dir  where to clone and build; default: ~/amethyst-intel-build
#   --install   copy the built Amethyst.app into /Applications when done
#
# Needs an Intel Mac, the Xcode Command Line Tools (xcode-select --install), git and
# curl. The first build takes 20 to 40 minutes, nearly all of it compiling.
set -euo pipefail

UPSTREAM="vitorpamplona/amethyst"
TAG=""
WORK="$HOME/amethyst-intel-build"
INSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --work-dir) WORK="$2"; shift 2 ;;
    --install) INSTALL=1; shift ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Checks.
[ "$(uname -s)" = "Darwin" ] || die "this script runs on macOS"
[ "$(uname -m)" = "x86_64" ] || die "this builds the Intel DMG, so it has to run on an Intel Mac (jpackage cannot cross-compile)"
xcode-select -p >/dev/null 2>&1 || die "install the Xcode Command Line Tools first: xcode-select --install"
for t in git curl shasum tar python3; do command -v "$t" >/dev/null 2>&1 || die "missing $t"; done
mkdir -p "$WORK"

# JDK 21 for x64: the one JAVA_HOME names, a system one, or one in ~/.jdks, whichever
# really is a 21 for x86_64 (java_home -v 21 also returns newer JDKs, and the build pins
# 21). Failing those, Temurin 21 is downloaded from Adoptium and its checksum verified.
jdk_ok() { [ -x "$1/bin/java" ] && "$1/bin/java" -version 2>&1 | head -1 | grep -q '"21' && file "$1/bin/java" | grep -q x86_64; }
JDK=""
for cand in "${JAVA_HOME:-}" "$(/usr/libexec/java_home -v 21 2>/dev/null || true)" "$HOME"/.jdks/jdk-21*/Contents/Home; do
  if [ -n "$cand" ] && jdk_ok "$cand"; then JDK="$cand"; break; fi
done
JAVA_HOME="$JDK"
if [ -z "$JAVA_HOME" ]; then
  say "Downloading Temurin JDK 21 for x64 into ~/.jdks"
  mkdir -p "$HOME/.jdks" "$WORK/downloads"
  meta="$WORK/downloads/jdk21.json"
  curl -fsSL "https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&os=mac&image_type=jdk&vendor=eclipse" -o "$meta"
  read -r link sum rel < <(python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1]))[0]; p=m["binary"]["package"]; print(p["link"], p["checksum"], m["release_name"])' "$meta")
  curl -fL --progress-bar -o "$WORK/downloads/jdk21.tar.gz" "$link"
  echo "$sum  $WORK/downloads/jdk21.tar.gz" | shasum -a 256 -c - >/dev/null || die "JDK checksum mismatch"
  tar -xzf "$WORK/downloads/jdk21.tar.gz" -C "$HOME/.jdks"
  JAVA_HOME="$HOME/.jdks/$rel/Contents/Home"
fi
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
say "JDK: $("$JAVA_HOME/bin/java" -version 2>&1 | head -1) ($JAVA_HOME)"

# Android SDK root. The desktop build never compiles anything for Android and
# downloads no SDK packages, but the Android Gradle plugin refuses to configure
# the shared modules without an SDK folder.
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
mkdir -p "$ANDROID_HOME"

# Upstream checkout at the release tag.
if [ -z "$TAG" ]; then
  TAG="$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$UPSTREAM/releases/latest" \
    | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
fi
VER="${TAG#v}"
SRC="$WORK/amethyst-$TAG"
if [ ! -d "$SRC/.git" ]; then
  say "Cloning $UPSTREAM at $TAG"
  git clone --depth 1 --branch "$TAG" "https://github.com/$UPSTREAM.git" "$SRC"
fi
grep -Eq "^app[[:space:]]*=[[:space:]]*\"$VER\"" "$SRC/gradle/libs.versions.toml" \
  || die "$SRC declares a different version than $TAG in gradle/libs.versions.toml"

# The one change to upstream: its build compiles the macOS video-player shim
# (desktopApp/native/macos-video-player) for arm64 whatever CPU runs the build, so an
# Intel package carries a dylib it cannot load, and video falls back to the library's
# own player, which crashes in its audio tap. This builds the shim for the CPU Gradle
# runs on. Proposed upstream; applied only while the checkout still hardcodes arm64.
if grep -q '"-arch", "arm64"' "$SRC/desktopApp/build.gradle.kts"; then
  say "Patching desktopApp/build.gradle.kts: build the video player shim for x86_64"
  git -C "$SRC" apply - <<'PATCH'
diff --git a/desktopApp/build.gradle.kts b/desktopApp/build.gradle.kts
index a245533..38b3fea 100644
--- a/desktopApp/build.gradle.kts
+++ b/desktopApp/build.gradle.kts
@@ -192,6 +192,12 @@ abstract class BuildMacVideoPlayer
         @get:Input
         abstract val jdkHome: Property<String>
 
+        // The CPU the package is for: the one Gradle runs on, like everything jpackage bundles. A
+        // dylib for the other one is refused by dlopen ("incompatible architecture"), and the app
+        // then falls back to the library's own player, with the audio tap that crashes.
+        @get:Input
+        abstract val arch: Property<String>
+
         @get:OutputDirectory
         abstract val output: DirectoryProperty
 
@@ -204,12 +210,12 @@ abstract class BuildMacVideoPlayer
                     "update it or drop it (see its README)"
             }
             val out = output.get().asFile.apply { mkdirs() }
-            val target = "arm64-apple-macosx14.0"
+            val target = "${arch.get()}-apple-macosx14.0"
             val bridge = File(temporaryDir, "jni_bridge.o")
             val jdk = jdkHome.get()
             exec.exec {
                 commandLine(
-                    "clang", "-c", "-arch", "arm64", "-target", target,
+                    "clang", "-c", "-arch", arch.get(), "-target", target,
                     "-I$jdk/include", "-I$jdk/include/darwin",
                     File(dir, "jni_bridge.c").path, "-o", bridge.path,
                 )
@@ -232,6 +238,7 @@ val buildMacVideoPlayer =
         sources.set(layout.projectDirectory.dir("native/macos-video-player"))
         libraryVersion.set(libs.versions.composemediaplayer.get())
         jdkHome.set(System.getProperty("java.home"))
+        arch.set(if (System.getProperty("os.arch") in setOf("aarch64", "arm64")) "arm64" else "x86_64")
         output.set(layout.buildDirectory.dir("macVideoPlayer"))
         onlyIf { isMacHost }
     }
PATCH
fi

# Build. This is upstream's own release task.
say "Building Amethyst $VER for x86_64 (the slow part)"
cd "$SRC"
if ! ./gradlew --no-daemon :desktopApp:packageReleaseDmg; then
  say "The build failed once; that is usually a download hiccup, so trying again"
  ./gradlew --no-daemon :desktopApp:packageReleaseDmg
fi

APP="$SRC/desktopApp/build/compose/binaries/main-release/app/Amethyst.app"
DMG="$(ls "$SRC"/desktopApp/build/compose/binaries/main-release/dmg/*.dmg | head -1)"
OUT="$WORK/dist/amethyst-desktop-$VER-macos-x64.dmg"
mkdir -p "$WORK/dist"
cp "$DMG" "$OUT"
( cd "$WORK/dist" && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256" )

say "Done"
echo "DMG:    $OUT"
echo "sha256: $(cut -d' ' -f1 "$OUT.sha256")"
echo "binary: $(file -b "$APP/Contents/MacOS/Amethyst")"
SHIM="$APP/Contents/app/resources/libNativeVideoPlayer.dylib"
if [ -f "$SHIM" ]; then
  file -b "$SHIM" | grep -q x86_64 || die "the video player shim is not x86_64; the patch did not take"
  echo "video shim: x86_64"
fi

if [ "$INSTALL" = 1 ]; then
  say "Installing /Applications/Amethyst.app"
  rm -rf /Applications/Amethyst.app
  cp -R "$APP" /Applications/Amethyst.app
  echo "Installed. It was built here, so macOS does not quarantine it; it opens like any other app."
fi
