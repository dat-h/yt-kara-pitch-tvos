#!/bin/sh
# Checks that a YouTube video resolves to a playable stream and that AVFoundation loads it, using
# the app's own resolver, in the tvOS Simulator. With --music, shows the music video the app would
# pair with a karaoke video instead. Run from the repo root:
#   sh scripts/check-stream.sh 'https://www.youtube.com/watch?v=IXbnzEHZDPg'
#   sh scripts/check-stream.sh --music 'https://www.youtube.com/watch?v=WHayJZ3eMcE'
# Uses an already booted Apple TV simulator (booting one takes minutes); set DESTINATION to override.
set -eu

music=0
test='StreamCheckLiveTests/resolvesAndLoads()'
if [ "${1:-}" = "--music" ]; then
    music=1
    test='StreamCheckLiveTests/findsTheMusicVideo()'
    shift
fi
[ $# -eq 1 ] || { echo "usage: $0 [--music] <youtube-url>" >&2; exit 2; }
booted=$(xcrun simctl list devices booted | sed -n 's/.*Apple TV.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' | head -n 1)
if [ -n "${DESTINATION:-}" ]; then
    destination=$DESTINATION
elif [ -n "$booted" ]; then
    destination="platform=tvOS Simulator,id=$booted"
else
    echo "no Apple TV simulator is booted: boot one, or set DESTINATION" >&2
    exit 2
fi
out=$(mktemp -t check-stream)
trap 'rm -f "$out"' EXIT

status=0
TEST_RUNNER_KARA_CHECK_URL="$1" TEST_RUNNER_KARA_CHECK_OUT="$out" TEST_RUNNER_KARA_CHECK_MUSIC="$music" \
    xcodebuild test -quiet -scheme KaraPitchTV -destination "$destination" -parallel-testing-enabled NO -collect-test-diagnostics never \
    "-only-testing:KaraPitchTVTests/$test" >/dev/null 2>&1 || status=$?

if [ -s "$out" ]; then
    cat "$out"
else
    echo "no report: the test didn't run (xcodebuild exit $status)" >&2
fi
exit "$status"
