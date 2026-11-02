Changes applied to the upstream checkout before building. Each is proposed upstream; `build.sh` skips a patch once the checkout no longer needs it.

- `0001-macos-video-player-host-cpu.patch`: upstream compiles its macOS video-player shim (`desktopApp/native/macos-video-player`) for arm64 whatever CPU runs the build, so an Intel package carries a dylib it cannot load and video falls back to the library's own player, which crashes in its audio tap. The patch builds the shim for the CPU Gradle runs on. Same change as the second commit on the proposal branch.
