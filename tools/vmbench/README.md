# vmbench

A benchmark to run **inside the virtual Mac**, for A/B of Henge's Performance settings
(Settings → Performance: *Mac refresh rate*, *Superblocks*, *Grouped memory checks*,
*Faster loop exits*) and of translator changes in general.

`tests/test_bench.c` is the host-side counterpart: it times translated code directly, which is
useful while changing the translator, but it is not the Mac. vmbench runs in the guest, so a
number here is what the Mac actually gets — JIT, chained blocks, page checks and all.

## Build

```sh
make vmbench            # -> build/vmbench (arm64, macOS 12+)
```

`tools/vmbench/vmbench` is that binary, committed so `run.sh` can serve it: after changing
`vmbench.c`, `make vmbench && cp build/vmbench tools/vmbench/vmbench && codesign -f -s -
tools/vmbench/vmbench` keeps the two the same.

## Get it into the Mac

The prebuilt binary is committed next to this file (`tools/vmbench/vmbench`, arm64, signed ad
hoc so macOS will run it), so the Mac can fetch and run it in one line — no files to move, no
share to set up:

```sh
curl -fsSL https://raw.githubusercontent.com/hazerbvisor/Henge-Custom/main/tools/vmbench/run.sh | sh
```

That is `run.sh` (next to this file): it downloads the binary into `$TMPDIR`, marks it
executable, and runs it with whatever arguments follow:

```sh
curl -fsSL .../tools/vmbench/run.sh | sh -s -- --runs 9 --save ~/base.txt
```

Served from this fork (`hazerbvisor/Henge-Custom`), main branch. On another fork, change
the `hazerbvisor/Henge-Custom/main` URL in `run.sh` to that fork's (or pass
`VMBENCH_BASE`, or just fetch `tools/vmbench/vmbench` from it by hand). Rebuilding with
`make vmbench` and committing the new binary is what keeps the two in step.

By hand, from the shared folder (Files › Henge › Shared, or `~/Henge` in the Mac once the Set
Up Command has been typed) — note a WebDAV share is not executable, so copy it out first:

```sh
cp ~/Henge/vmbench ~/vmbench && chmod +x ~/vmbench && ~/vmbench
```

## Run

```sh
~/vmbench                     # every kernel, best of 5, about 8 s
~/vmbench --runs 9            # more repeats when the Mac is busy
~/vmbench --save base.txt     # save the numbers
~/vmbench --baseline base.txt # compare against them
```

Each kernel does a fixed shape of work (see the header of `vmbench.c`): `calls` (recursive
calls and stack frames), `stackmem` (read-modify-write of a stack buffer), `chase` (dependent
loads over 256 pages), `loop` (a tight arithmetic loop), `dispatch` (a switch interpreter) and
`sieve` (memory and nested loops). Start-up scales each one to about 0.15 s, then the best of
N timed runs is reported, so run-to-run noise from the host stays small.

## A/B of a setting

1. With the setting off, `~/vmbench --save ~/base.txt`.
2. Quit Henge and start the Mac again (the Performance settings are read when a Mac starts),
   switch the one setting on.
3. `~/vmbench --baseline ~/base.txt`.

`us/rep` is the time for one unit of that kernel's work: lower is faster. `overall` is the
geometric mean of the six ratios, so one kernel's noise does not dominate. Change one setting
at a time — *Mac refresh rate* changes the whole workload, so measure it on its own.

The checksum at the end must be identical between runs, and `--baseline` prints
`WRONG RESULT` and names the kernel when it is not: that is a translation bug, not a speed
difference. Compare runs on a Mac that is otherwise idle; the first minutes after login are
not a fair baseline (macOS is still starting up in the background).
