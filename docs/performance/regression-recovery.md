# Regression recovery for PR #6

The reported iPad regression (CPU frame times 16–40 ms) is not reproduced or
explained conclusively on this Mac. Stable ~16 ms and higher Roblox FPS remain
**unverified targets**. This report supersedes the earlier audit's cache-warming
recommendation and runtime-only HV_PERF activation instructions.

## Findings

The affected workflow 42448286754 succeeded and its downloaded manifest pins
8ff5f8d with Husk afe83d45. Inspection of the IPA's app/helper/framework Info.plists
found no LSEnvironment entries. Repository source, packaging and workflow do not
set HV_PERF. Its initialization required exactly HV_PERF=1, so CPU diagnostics
were off under the default launch configuration. The GPU preference defaults off,
but henge.gpu.diagnostics is a persisted user opt-in. The IPA does not contain the
iPad's UserDefaults or launch environment. Whether diagnostics were enabled in
the affected session cannot be established without its launch/graphics log or
settings. Do not infer runtime enablement just from format strings in a binary.

Source-level diagnostic costs were confirmed: runtime flag branches around new
per-dispatch timers even when off; two timestamp calls per dispatcher return
when enabled, periodic formatting on vCPU threads, and per-command queue timing
when enabled. Original PVG replay also took three now_seconds timestamps per exec
and printed an unconditional summary every 2,000 execs. These predate this PR,
so they are overhead candidates, **not an established cause of the regression**.
Resource replay also called getenv(HV_PVG_TALLY) for each resource; cursor and heap
logging re-read their environment flags repeatedly. Essential rendering/pacing
clocks, completion checks, errors, crash handling and iBoot diagnostics remain.

The translator, software MMU/TLB, emitted block chaining, code invalidation,
JIT cache capacity, scheduling QoS, WFI/WFE/timer policy and locks have no code
changes versus cd36195. No profile establishes that their costs grew. Existing
TLBI waits, device serialization, code flushes and host/guest thread competition
remain candidates for six-vCPU spikes, requiring on-device profiles. Four and six
cannot be ranked from these single-vCPU native tests. No guest Roblox sample was
available to determine ARM64 versus Rosetta execution or guest process CPU time.

## Focused changes (engine commit 2cec34b)

1. Normal builds use PERF_DIAGNOSTICS=0. The compiler removes the new CPU/PVG
   timing branches, counters, clocks and formatted reports, even if HV_PERF=1 is
   injected at runtime. Tests exercise that override and the IPA validator rejects
   new timing format strings in the packaged release executable.
2. Roll back the unproven newly-published-block cache warming to baseline lookup
   behavior. This is a conservative rollback for comparison, not proof that the
   fill was incorrect or caused the regression. Generation/PA/flags validity
   checks and full-flush behavior remain tested.
3. Keep race-free per-vCPU debug history but place it and diagnostic counters at
   the tail of HvPerCpu, away from interrupt lines and existing hot lookup fields.
   This avoids inserting diagnostic storage into the original field layout; no
   measured false-sharing benefit is claimed.
4. Gate the inherited three replay timing reads and 2,000-exec summary behind
   the existing GPU diagnostics opt-in. Cache tally/cursor/heap logging flags once
   per renderer. Those environment switches now require renderer recreation to
   change. No Metal command, completion, barrier or presentation ordering changed.

Advanced CPU timing requires a separate build directory and explicit opt-in:
`make B=build/diagnostics PERF_DIAGNOSTICS=1 test-engine`, then launch that build
with HV_PERF=1. For iOS, clean/rebuild the engine with PERF_DIAGNOSTICS=1 and use
an explicit launch environment. Existing GPU diagnostics remain available through
the app setting, off by default. Use diagnostics off for primary FPS comparisons.

## Repeatable native latency measurements

All three sources use the same updated test_bench.c and -O2. Baseline cd36195,
affected 8ff5f8d, recovery 2cec34b. HV_PERF unset, single-vCPU synthetic workloads,
ARM64 macOS 27.2 Command Line Tools. HV_BENCH_LATENCY=1 records 51 warm JIT
whole-program durations after one warmup, including CPU reset and dispatcher
entry; sorted nearest-rank P95 (49th) and P99 (51st). These are neither Roblox
frame times nor isolated dispatcher lookup times. Three rounds alternate source
order; table entries are medians of the three per-run summary statistics, not
pooled percentiles. Raw outputs: recovery-latency.json. Background host activity
is uncontrolled. An initial run concurrent with compilation was discarded before
this repeated series.

| Workload | Baseline median/P95/P99 ms | Affected median/P95/P99 ms | Recovery median/P95/P99 ms |
|---|---|---|---|
| bench_calls | 3.156/3.505/4.076 | 3.198/4.027/4.968 | 3.179/3.712/4.398 |
| bench_mem | 2.136/2.348/2.920 | 2.164/2.532/2.830 | 2.180/2.569/2.755 |
| bench_dispatch | 4.291/4.920/5.435 | 4.341/5.148/6.025 | 4.346/4.826/4.943 |
| bench_loop | 2.081/2.378/2.884 | 2.080/2.288/2.377 | 2.080/2.325/2.474 |

The small and mixed differences do not demonstrate restoration of game frame
pacing. These mostly chained workloads spend little time in the changed paths.
No native GPU throughput or actual VM four/six-vCPU scaling is measured.

Reproduce by archiving cd36195 and 8ff5f8d to separate build-only directories,
copying this revision's tests/test_bench.c into each, building build/test_bench,
and running each with HV_BENCH_LATENCY=1 in alternating order. Do not use guest
disk images for these benchmarks.

## Validation and delivery

Local release and diagnostic test-engine suites pass: classification, operands,
MAP_JIT/split regions, JIT/PAC/full-cache stress, MMU, memory, exceptions, devices
(103 checks, including 64/128/256/512 GiB BDIF capacity) and cache invalidation /
history checks. GPU decoder/replay recording and upstream negative-control tests
pass; native GPU pixel tests skip because this host exposes no Metal device.
Mouse integration and display lifecycle tests pass (Swift cache access required
sandbox escalation). New CPU and PVG timing strings are absent from normal object
files. BDIF, translator, MMU, JIT allocator/assembly, shared input, audio/network
and sparse disk implementation remain unchanged from the working baseline.
No existing guest disk image was opened or modified; device tests use new /tmp
fixtures. Local full app/IPA build remains unavailable without full Xcode/iOS SDK.

GitHub Actions run 42450457742 builds the pinned recovery engine on ARM64 Xcode 27,
runs release and diagnostic engine tests, GPU/input regressions, packages the IPA,
and validates binary architecture, JIT protections/entitlements, BDIF markers,
provenance and absence of the new hot-path timing strings. Run completed successfully; downloadable artifact:
https://github.com/hazerbvisor/Henge-Custom/actions/runs/42450457742/artifacts/13605606134

The downloaded IPA ZIP, engine commit, SHA256, BDIF marker and absence of new
timing markers were independently checked locally. Provenance is saved in
recovery-build-manifest.json. The runner also passed native Metal offscreen
geometry, depth and dynamic-buffer pixel tests on its Apple Paravirtual device,
with no GPU skips. This still does not replace physical iPad validation. PR #6 remains unmerged.

## Required iPad comparison

Use cd36195, the affected IPA and the recovery IPA at identical 8 GiB RAM, 1024 MiB
JIT, existing 128 GiB disk, resolution, graphics quality and FPS cap. Fully stop
the VM before changing four/six vCPUs; never open the same disk concurrently.
Do not reinstall or resize. Disable GPU diagnostics for main measurements and
record whether the previous setting was on. Keep power/thermal conditions stable.
Warm each fixed Prison Life / heavier-game scene for two minutes, then capture
three 120-second runs for each build x vCPU count in alternating order. Record
raw game frame times (median/P95/P99), CPU/GPU timing, FPS, temperatures and stalls.
Check guest Activity Monitor Kind or a Roblox process sample for architecture;
compare guest Roblox samples with host Henge vCPU/PVG/System Trace samples.
Use a separate diagnostic pass to attribute translation, misses, flushes, lock
waits or queue growth; its overhead is not representative of the release IPA.
Verify macOS 27.2 boot, capacity 268435456 sectors, mouse/keyboard, networking,
audio and rendering. Do not call the target achieved until these measurements
show CPU spikes reduced. Full protocol and interpretation: audit.md.
