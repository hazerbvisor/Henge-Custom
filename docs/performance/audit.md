# CPU / JIT performance audit

## Scope and conclusion

Target supplied by the owner: iPad Air M4 / iPadOS 27.0.1, macOS 27.2 ARM64 guest,
128 GiB sparse disk, 8 GiB RAM, 6 vCPUs, 1024 MiB JIT. Owner-observed Roblox:
Prison Life generally above 50 FPS, light games 50–60 FPS, heavier games around
30 FPS; reported CPU frame time ~16 ms and GPU time ~4 ms. These are user
observations, not measurements collected by this change.

CPU pressure is plausible, not established. A 16 ms game CPU frame approaches a
60 Hz budget, but 30 FPS can also reflect a cap, missed presentation deadlines,
asset/IO stalls, host descheduling, memory pressure or GPU queue backpressure.
CPU and GPU frame times can overlap; do not add them to infer FPS. No on-device
Roblox run, macOS boot or 4/6-vCPU VM comparison was possible on this host.

The branch combines the sparse installer branch at `6f948a0` with the separate
confirmed BDIF boot fix branch at `cd36195`. The latter was discovered to be
absent from the former during cross-branch validation and merged intact. BDIF,
its header and host boot diagnostics match `cd36195` exactly. Capacity remains
actual bytes / 512, including auxiliary header exclusion; no 64 GiB constant.

## Architecture and evidence

- `core/translate.c`: ARM64-to-ARM64 DBT, hot/cold emission buffers, inline RAM
  TLB checks, out-of-line helpers, direct block chaining, cross-page mapping
  checks, indirect branch cache and return cache. Translation is thread-local;
  code placement reserves space atomically, then publication takes `tr_mu`.
  Already avoids a single translation lock around all generation. Duplicate
  translations can consume region space before the publication recheck; new
  diagnostics count them. Changing reservation/publication requires more data.
- `core/dispatch.c`: front cache followed by shared block hash. A newly published
  block previously skipped the front-cache fill, requiring another hash lookup
  if revisited through the dispatcher. The fill now uses the exact published
  block, preserving PA, execution flags and page-generation checks. No lookup
  validity conditions or invalidations were removed.
- Dispatcher debug history previously wrote one shared ring and cursor on every
  entry, even with statistics disabled. Now each vCPU owns its history and crash
  reports read that CPU's ring. Removes these cross-vCPU writes and their race;
  does not claim to eliminate all shared statistics races.
- `host/jit_region.c`, `host/enter.S`: executable region allocation, split RX/RW
  aliases or MAP_JIT, per-thread write protection, atomic instruction patches,
  instruction-cache invalidation and entry ISB. Unchanged. Full cache eviction
  still uses stop-the-world; page invalidation still protects code and drops
  cached targets. The 1024 MiB region can reduce capacity flushes, but code
  expansion, block-table limits and duplicates must be measured before tuning.
- `core/mmu.c`, `core/memop.c`: inline software TLB, light refill path, slow MMIO /
  code writes / page crossings, ASID caches and saved user TLBs. TLB churn and
  instruction expansion remain strong suspects. `mmu.c` must retain
  `-mgeneral-regs-only`: helpers execute with guest SIMD state live. Unchanged.
- `host/vm.c`: vCPU pthreads; user-initiated QoS by default on iOS; 1 ms kicker.
  `HV_QOS` already permits testing default/init/ui. More vCPUs can increase
  host competition, TLBI acknowledgement waits, device-lock contention and
  translation duplicates. Six cannot be assumed faster than four. QoS, wakeup
  ordering and timer deadlines are unchanged.
- WFI parks on a per-CPU condition variable with timer deadline and pending wake
  checks; WFE waits on the monitored word for a bounded period. TLBI handshakes,
  stop-the-world and device locking are correctness-sensitive. No spin budget,
  memory ordering or protection was weakened.
- `devices/pvg_lite.c`: command-ring decoding, barrier drains, command allocation
  and copy, serial-worker dispatch. `devices/pvg_metal.m`: replay, resource lookup,
  encoding, submission, separate serial presenter and drawable retries. Per-command
  allocations, serial dispatch and synchronous replay work are suspects, not
  measured bottlenecks. Existing Metal ordering, validation, geometry fixes,
  drawable retry behavior and frame coalescing are unchanged.

## Optional diagnostics

Set **HV_PERF=1 before starting the process** (Xcode scheme environment on iOS).
Unset or any other value disables it. Configuration is immutable after machine /
renderer creation. No timing calls, allocation, new lock or histogram work occurs
on disabled paths; there is a flag check at instrumented boundaries. This is not
literally zero overhead; its impact on the target still needs measurement.

Each vCPU reports cumulative integer counters every 65,536 dispatcher returns:
`entries` (returns to the dispatcher), dispatcher `lookup`, `front`, `hash`,
`miss`, translation attempts / duplicates, translation microseconds,
`residency_us`, WFI wakes / idle microseconds, publication-lock wait count / time.
The counters are owner-written; no new shared counter contention. Front/hash
statistics describe the dispatcher lookup, not all generated-code cache probes.
Residency includes execution, helpers and host descheduling; translation timing
covers emission, not placement and cache maintenance. Wakes include timeouts and
spurious condition-variable returns, not just interrupts. Powered-off waits are
not included. Short runs may not reach the reporting threshold.

PVG reports every 256 processed commands: `pvg_queue` (enqueue to worker start)
and `pvg_processing` (decode/replay/submission wall time). Presenter reports every
120 intervals: `present_commit_interval`. Each distribution contains count,
average, P95/P99 bucket upper bounds and maximum in microseconds. Fixed logarithmic
buckets avoid allocation and sorting; percentiles are approximate, not exact.
Presentation commit intervals include idle/cursor activity and do not establish
actual screen presentation, GPU execution duration, or Roblox frame times.
Logging perturbs diagnostics runs; measure FPS with diagnostics off as well.

Existing desktop `--stats` / `--profile` expose helper transitions, slow memory
causes, TLB misses/refills, flush reasons, TLBI waits, device-lock waits, translation
expansion and host PC samples. Legacy shared statistics are approximate under SMP
and are not made race-free here. CPU0 thread utilization is not total VM CPU use.
No hardware TLB-miss counter or OS scheduler tracing is supplied by this patch.
Use Instruments Time Profiler, System Trace and Metal System Trace on a development
build for those questions, checking guest JIT residency against host helper and
PVG worker samples. Host samples alone cannot identify guest process ownership.

## Native measurements

Host: ARM64 macOS 27.2 (26B123), Command Line Tools clang, `-O2`, no exposed Metal
device. `native-comparison.json` preserves all samples and host metadata. Baseline
binary was built from `6f948a0` before edits; CPU engine code is identical to the
BDIF boot-fix branch. Optimized CPU code: `c41d29c`; HV_PERF unset. Seven alternating
process runs per binary; each existing benchmark returns its best native-of-five
and warm-JIT-of-four. These are medians of those minima, not frame percentiles.

| Program | Baseline native ms | Baseline JIT ms | Optimized native ms | Optimized JIT ms |
|---|---:|---:|---:|---:|
| calls | 0.560 | 2.409 | 0.529 | 2.294 |
| memory | 0.449 | 1.639 | 0.449 | 1.650 |
| indirect dispatch | 0.640 | 3.240 | 0.653 | 3.256 |
| chained loop | 0.936 | 1.625 | 0.862 | 1.572 |

These tiny single-vCPU workloads mostly remain inside chained code (one warm
entry), so they do not isolate the changed dispatcher paths. Native timing also
varies. Results do **not** establish a speedup or regression; no FPS improvement
is claimed. The deterministic cache regression establishes the eliminated hash
lookup, and source ownership establishes removal of shared debug-history writes.
Four/six-vCPU guest and Roblox results remain unmeasured.

Reproduce from clean source snapshots without touching guest disks:

```sh
# Build baseline in a separate directory from this source archive:
mkdir -p build/baseline-source
git archive cd36195 | tar -x -C build/baseline-source
make -C build/baseline-source build/test_bench
make build/test_bench
python3 tools/benchmark_cpu.py build/baseline-source/build/test_bench build/test_bench > build/comparison.json
make test-engine test-display-routing
ios/scripts/check_mouse_buttons.sh
ios/scripts/check_gpu.sh
```

## Validation and limits

See `validation.txt` for final results. All fixture files belong to a unique new
`/tmp/henge-devices-*` directory; no existing guest image was opened, resized,
reset or removed. Capacity tests change only test metadata in memory. Device
fixtures previously used a developer-specific `/Volumes` path; this was repaired
rather than requesting access to an unrelated volume. Native-reference test
helpers exceed the default main-thread stack when inlined by this clang; the
Makefile gives only test executables a 64 MiB stack. App stack settings unchanged.

`make test` also builds desktop applications and fails here because `pkg-config`
and `libslirp.h` are absent. `make test-engine` independently builds/runs the
complete engine/device regression list. IPA compilation was attempted with
`make ios-lib`: `xcrun` cannot locate `iphoneos`; downstream compilation then lacks
`pthread.h`. Only Command Line Tools are installed; no full Xcode or xcodegen.
No IPA was compiled, packaged, signed or validated. Native Metal pixel tests
explicitly skip because this host has no Metal device. No on-device graphical,
networking/audio, boot or JIT entitlement validation is implied by unit tests.

## On-device comparison protocol

1. Use baseline `cd36195` and this branch, same pinned dependencies, optimization
   flags and signing/JIT route. Full Xcode 27+, iOS SDK, xcodegen and dependencies
   in `ios/README.md` are required. Run the repository packaging/IPA validator
   before installing. Never run restore, expansion or disk recreation for testing.
2. Keep 128 GiB capacity, 8 GiB RAM, 1024 MiB JIT, guest resolution, refresh rate,
   Roblox graphics quality and FPS cap fixed. Change only vCPUs between four and
   six while the VM is fully stopped, through existing configuration. Record
   device power, thermal state and background workload. Do not run both builds
   against the disk concurrently.
3. After boot, let background work settle; warm the same scene for two minutes.
   Alternate baseline-4, optimized-4, optimized-6, baseline-6, then reverse order.
   Record at least three 120-second runs per cell for Prison Life and one named
   heavier game. Use the same route/camera and comparable server population;
   annotate network/asset stalls. Separately time cold boot/first launch.
4. Record Roblox CPU/GPU timing and raw frame durations (MicroProfiler export if
   available), FPS, average/P95/P99 frame time, host Henge CPU use, guest Roblox
   CPU use, memory pressure, thermal state and screenshots of problem scenes.
   Compute frame percentiles from game frames; do not substitute the PVG commit
   histogram. Run diagnostics-on passes separately and compare their overhead.
5. **Determine the actual running Roblox architecture inside the guest.** In
   guest Activity Monitor inspect Roblox's Kind (Apple/Intel); take a process
   sample and retain its Code Type / translation indication. `file`/`lipo -archs`
   on RobloxPlayer identifies available slices but cannot prove the chosen one.
   Do not use host Roblox or `sysctl.proc_translated` from a separate Terminal
   process as evidence about guest Roblox. Architecture remains unknown here.
6. Compare guest Roblox main/render thread samples with Henge vCPU, translator,
   device-lock and PVG-worker samples. A busy game main thread with low translation
   cost suggests guest work; high translator/slow-memory/lock time suggests host
   overhead; queue growth or drawable stalls point to submission/presentation.
   Rosetta would add another translation layer and warrants its own comparison.
7. Confirm macOS 27.2 boot with the existing 128 GiB disk, capacity log of
   268435456 sectors, graphics/screenshots, mouse buttons/drag, network traffic,
   audio and JIT setup. Stop on corruption, boot failures or new rendering faults.

Remaining risks: target-specific scheduling and thermal behavior, legacy shared
statistics races, approximate percentile buckets and instrumentation perturbation,
private Metal compatibility, and missing real-device concurrency/pixel validation.
Do not expand this patch into cache invalidation, synchronization or pacing policy
changes without the above profiles.
