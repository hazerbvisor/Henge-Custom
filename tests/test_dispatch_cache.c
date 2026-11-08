/* Regression: lookup must reject stale cache entries;
   page invalidation and full flush must still reject stale code. */
#include "dispatch.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>

static int step(HvCpu *cpu) {
    cpu->pc = 0x4000;
    return hv_run_one(cpu);
}

int main(void) {
    static HvMachine m;
    static HvCpu a, b;
    setenv("HV_PERF", "1", 1);
    assert(hv_machine_init(&m, 4 << 20) == 0);
    assert(m.perf_enabled == HV_ENABLE_PERF);
    m.perf_enabled = 1;
    m.chain = 0;
    uint32_t *ram = aligned_alloc(16384, 16384);
    assert(ram);
    ram[0] = 0x14001000; /* B to another guest page: never an in-block loop. */
    assert(hv_machine_add_ram(&m, 0x4000, 16384, ram, 0) == 0);
    hv_cpu_reset(&a, &m);
    hv_cpu_reset_index(&b, &m, 1);
    a.pc = b.pc = 0x4000;
    assert(step(&a) == HV_EXIT_BRANCH);
    if (HV_ENABLE_PERF) assert(a.pc_state->perf.misses == 1);
    assert(step(&a) == HV_EXIT_BRANCH);
    if (HV_ENABLE_PERF) assert(a.pc_state->perf.front_hits == 0);
    if (HV_ENABLE_PERF) assert(a.pc_state->perf.hash_hits == 1);
    assert(step(&b) == HV_EXIT_BRANCH);
    if (HV_ENABLE_PERF) assert(b.pc_state->perf.hash_hits == 1);
    assert(step(&b) == HV_EXIT_BRANCH);
    if (HV_ENABLE_PERF) assert(b.pc_state->perf.front_hits == 1);
    hv_invalidate_code(&m, 0x4000);
    assert(step(&a) == HV_EXIT_BRANCH);
    if (HV_ENABLE_PERF) assert(a.pc_state->perf.misses == 2);
    hv_flush_blocks(&m); /* both CPUs are parked after hv_run_one */
    assert(step(&a) == HV_EXIT_BRANCH);
    if (HV_ENABLE_PERF) assert(a.pc_state->perf.misses == 3);
    assert(step(&a) == HV_EXIT_BRANCH);
    if (HV_ENABLE_PERF) assert(a.pc_state->perf.front_hits == 0);
    assert(a.pc_state->nrecent == 5 && b.pc_state->nrecent == 2);
    assert(a.pc_state->recent[0] == (0x4000 | a.el));
    hv_machine_free(&m);
    free(ram);
    puts("PASS: baseline cache lookup, per-CPU isolation, code invalidation, flush and history");
}
