#ifndef HENGE_PERF_H
#define HENGE_PERF_H
#include <stdint.h>

/* Single-owner histogram, in microseconds. Percentiles are bucket upper bounds.
   No allocation, locks, or clock reads in record/percentile. */
typedef struct HvPerfDist {
    uint64_t count, total_us, max_us, buckets[32];
} HvPerfDist;
static inline void hv_perf_record(HvPerfDist *d, uint64_t us) {
    unsigned b = 0;
    uint64_t v = us;
    while (v > 1 && b < 31) { v = (v >> 1) + (v & 1); b++; }
    d->buckets[b]++;
    d->count++;
    d->total_us += us;
    if (us > d->max_us) d->max_us = us;
}
static inline uint64_t hv_perf_percentile(const HvPerfDist *d, unsigned pct) {
    if (!d->count) return 0;
    uint64_t rank = (d->count / 100) * pct + ((d->count % 100) * pct + 99) / 100;
    uint64_t n = 0;
    for (unsigned b = 0; b < 32; b++) {
        n += d->buckets[b];
        if (n >= rank) return b == 31 ? d->max_us : 1ull << b;
    }
    return d->max_us;
}
/* Written and reported only by the owning vCPU, never a shared hot counter. */
typedef struct HvCpuPerf {
    uint64_t lookups, front_hits, hash_hits, misses, translations, duplicate_translations;
    uint64_t translate_ticks, execute_ticks, entries, idle_ticks, wakes;
    uint64_t publish_wait_ticks, publish_waits;
} HvCpuPerf;
#endif
