#!/bin/bash
# Compile actual replay methods against Metal; always run recording tests, and run
# native offscreen image tests when this machine exposes a Metal device.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/gpu-check
xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror -Idevices \
  tests/test_pvg_decode.c -o build/gpu-check/test-pvg-decode
build/gpu-check/test-pvg-decode
compile_replay() {
  local output="$1" replay_source="${2:-}"
  local replay_defines=()
  if [[ -n "$replay_source" ]]; then
    [[ "$replay_source" = /* ]] || replay_source="$PWD/$replay_source"
    replay_defines+=("-DPVG_REPLAY_SOURCE=\"$replay_source\"")
  fi
  xcrun --sdk macosx clang -fobjc-arc -O1 -g -std=c11 -Wall -Wextra \
    -Wno-unused-parameter -Wno-deprecated-declarations -Wno-shadow-ivar \
    -Icore -Ihost -Idevices "${replay_defines[@]}" tests/test_pvg_replay.m \
    -framework Foundation -framework Metal -framework QuartzCore -framework IOSurface \
    -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers \
    -o "$output"
}
expect_original_regression() {
  set +e
  "$1" >build/gpu-check/prepatch.log 2>&1
  local replay_status=$?
  set -e
  cat build/gpu-check/prepatch.log
  [[ "$replay_status" = 1 ]] && grep -qx 'FAIL: truncated draw must be rejected before resource lookup or encoding' build/gpu-check/prepatch.log || {
    echo 'FAIL: baseline did not exhibit the expected adjacent-record draw regression' >&2; exit 1;
  }
  echo 'PASS: baseline source exhibits the expected adjacent-record draw regression'
}

compile_replay build/gpu-check/test-pvg-replay "${PVG_REPLAY_SOURCE:-}"
if [[ "${EXPECT_PREPATCH_FAILURE:-0}" = 1 ]]; then
  # Optional alternate-source proof. Compilation must still succeed; a crash or
  # a different failure does not establish the intended regression.
  [[ -n "${PVG_REPLAY_SOURCE:-}" ]] || { echo 'FAIL: prepatch proof requires PVG_REPLAY_SOURCE' >&2; exit 1; }
  expect_original_regression build/gpu-check/test-pvg-replay
else
  build/gpu-check/test-pvg-replay
  if [[ -z "${PVG_REPLAY_SOURCE:-}" ]]; then
    # Pin the original upstream source: this is a reproducible negative control,
    # while the same harness above must pass against the corrected source.
    git show da7332e32134f0aa14a67f8cbf67307e68f5367e:devices/pvg_metal.m >build/gpu-check/pvg-before.m
    compile_replay build/gpu-check/test-pvg-before build/gpu-check/pvg-before.m
    expect_original_regression build/gpu-check/test-pvg-before
  fi
fi
