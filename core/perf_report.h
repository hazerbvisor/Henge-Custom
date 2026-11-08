#ifndef HENGE_PERF_REPORT_H
#define HENGE_PERF_REPORT_H
#include "perf.h"
#include <stdio.h>
#include <mach/mach_time.h>
static inline uint64_t hv_perf_us(uint64_t ticks) {
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    return ((ticks / tb.denom) * tb.numer + (ticks % tb.denom) * tb.numer / tb.denom) / 1000;
}
static inline void hv_perf_print(const char *name, const HvPerfDist *d) {
    fprintf(stderr, "perf %s n=%llu avg_us=%llu p95_upper_us=%llu p99_upper_us=%llu max_us=%llu\n",
            name, (unsigned long long)d->count,
            (unsigned long long)(d->count ? d->total_us / d->count : 0),
            (unsigned long long)hv_perf_percentile(d, 95),
            (unsigned long long)hv_perf_percentile(d, 99), (unsigned long long)d->max_us);
}
#endif
