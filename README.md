# Kara Pitch for Apple TV

A karaoke player for Apple TV: YouTube videos at ±6 semitones, a LAN queue filled from phones, and
Siri Remote search. See [`SPEC.md`](SPEC.md) and [`PLAN.md`](PLAN.md).

**Status:** Spike 0 passed on the device with Approach A
([ADR 0001](docs/adr/0001-pitch-shift.md)). Playback, queue, phone web UI and HTTP API on :8080, TV polish (ticker, banner, control overlay) and TV search are in: all spec milestones are implemented.

## Build
Needs Xcode 16+. SmartTubeIOS is a pinned git submodule: clone with `--recurse-submodules`, or run
`git submodule update --init` after cloning.
The first package resolve also fetches Firebase, which only SmartTube's UI target uses, so it's slow.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -scheme KaraPitchTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'
# Phase 1a stream probe against the live network:
TEST_RUNNER_KARA_PROBE=1 xcodebuild test -scheme KaraPitchTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -only-testing:KaraPitchTVTests/StreamProbeLiveTests
```

## Install on an Apple TV (free Apple ID)
1. Open `KaraPitchTV.xcodeproj`, then Signing & Capabilities: pick your Personal Team and, if
   needed, change the bundle ID from `dev.ytkara.tv.greg`.
2. Pair the Apple TV: on the TV, Settings → Remotes and Devices → Remote App and Devices; on the
   Mac, Xcode → Devices and Simulators.
3. Choose the Apple TV as the run destination and press Run. Re-run every 7 days when the free
   profile expires.

## License
GPL-3.0, inherited from SmartTubeIOS.
