#!/bin/sh
# Fetches vmbench (Henge's guest benchmark) and runs it inside the Mac it is run in.
#
# In the Mac's Terminal (Terminal.app inside Henge), one line:
#
#     curl -fsSL https://raw.githubusercontent.com/hazerbvisor/Henge-Custom/main/tools/vmbench/run.sh | sh
#
# Arguments go through, so a longer run is:
#
#     curl -fsSL .../run.sh | sh -s -- --runs 9
#
# Set VMBENCH_BASE to take the binary from somewhere else (a fork, or a local server while
# testing):  VMBENCH_BASE=http://127.0.0.1:8000/tools/vmbench sh run.sh
#
# What it does: downloads the prebuilt arm64 binary next to this script's URL (tools/vmbench/vmbench
# in the repository, kept signed ad hoc so macOS runs it), puts it in the temporary folder, and
# runs it. Nothing is installed and nothing outside that folder is written. To keep it, move it to
# your home folder yourself: cp "$TMPDIR/vmbench" ~/vmbench && chmod +x ~/vmbench
set -e

base=${VMBENCH_BASE:-https://raw.githubusercontent.com/hazerbvisor/Henge-Custom/main/tools/vmbench}
dest=${TMPDIR:-/tmp}/vmbench

# curl -f: a 404 (a fork without the file, or a branch other than main) fails here and not later.
if ! curl -fsSL "$base/vmbench" -o "$dest"; then
    echo "vmbench: could not fetch $base/vmbench" >&2
    echo "vmbench: set VMBENCH_BASE to where tools/vmbench is served from, or copy the binary in by hand." >&2
    exit 1
fi
chmod +x "$dest"
# A copy that came through a share or a browser can carry a quarantine flag macOS refuses to run.
xattr -c "$dest" 2>/dev/null || true
exec "$dest" "$@"
