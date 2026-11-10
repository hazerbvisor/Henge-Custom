/* Emission only: does not execute guest code or open disks. */
#include "translate.h"
#include <mach/mach_time.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static uint32_t rng = 1;
static uint32_t next(void) { rng ^= rng << 13; rng ^= rng >> 17; return rng ^= rng << 5; }
int main(void) {
    static HvMachine m;
    static uint32_t code[4096][32];
    const uint32_t ops[] = {0x91000400,0x8b020021,0xf9400020,0xf9000420,0xd503201f,0xa9400c22};
    for (unsigned k = 0; k < 4096; ++k) {
        for (unsigned i = 0; i < 31; ++i) code[k][i] = ops[(i + k) % 6];
        code[k][31] = 0xd65f03c0;
    }
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    for (unsigned scenario = 0; scenario < 3; ++scenario) {
        if (scenario) for (unsigned k = 0; k < 4096; ++k)
            for (unsigned i = 0; i < 31; ++i) {
                // Valid ADD-immediate encodings with diverse register/immediate fields.
                code[k][i] = scenario == 1 ? 0x91000000 | (next() & 0x003fffff) : 0xf9400000 | (next() & 0x003fffff);
            }
        uint64_t checksum = 0, start = mach_absolute_time();
        for (unsigned k = 0; k < 100000; ++k) {
            HvBlock b = {.va=0x100000, .pa=0x100000};
            m.nslots = 0;
            if (hv_translate_emit(&m, &b, code[k & 4095], 32)) abort();
            checksum += b.ninsns + hv_translate_last_words();
        }
        double ms = (mach_absolute_time() - start) * (double)tb.numer / tb.denom / 1e6;
        printf("%s emission_ms=%.3f checksum=%llu\n", scenario == 2 ? "diverse-memory" : scenario ? "diverse-alu" : "repeated", ms, (unsigned long long)checksum);
    }
}
