#include "perf_report.h"
#include <assert.h>
#include <limits.h>
int main(void) {
    HvPerfDist d = {0};
    assert(hv_perf_percentile(&d, 95) == 0);
    for (unsigned i = 1; i <= 100; i++) hv_perf_record(&d, i);
    assert(d.count == 100 && d.total_us == 5050 && d.max_us == 100);
    assert(hv_perf_percentile(&d, 50) == 64);
    assert(hv_perf_percentile(&d, 95) == 128);
    assert(hv_perf_percentile(&d, 99) == 128);
    HvPerfDist edges = {0};
    hv_perf_record(&edges, 0);
    hv_perf_record(&edges, 1);
    hv_perf_record(&edges, 2);
    hv_perf_record(&edges, UINT64_MAX / 2);
    assert(hv_perf_percentile(&edges, 100) == UINT64_MAX / 2);
    assert(hv_perf_us(0) == 0);
    puts("PASS: optional performance histogram boundaries and percentile ranks");
}
