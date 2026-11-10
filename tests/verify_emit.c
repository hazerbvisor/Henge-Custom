#include "translate.h"
#include <stdio.h>
#include <stdlib.h>
extern int reference_emit(HvMachine *, HvBlock *, const uint32_t *, uint32_t);
extern uint64_t reference_hash(void), candidate_hash(void);
int main(void) {
    static HvMachine m;
    uint32_t rng = 1, code[32];
    for (unsigned trial = 0; trial < 20000; trial++) {
        for (unsigned i = 0; i < 31; i++) {
            rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
            code[i] = trial < 10000 ? 0x91000000 | (rng & 0x003fffff) : rng;
        }
        code[31] = 0xd65f03c0;
        /* Exercise both code layouts, grouped fallback and slow-memory helpers. */
        hv_knob[HV_K_TEST2] = trial & 1;
        hv_knob[HV_K_GROUPS] = (trial >> 1) & 1;
        m.slow_mem = (trial >> 2) & 1;
        HvBlock a = {.va=0x100000, .pa=0x100000, .flags=(trial >> 3) % 16}, b = a;
        m.nslots = 0;
        int ra = reference_emit(&m, &a, code, 32);
        uint64_t hash = reference_hash();
        m.nslots = 0;
        int rb = hv_translate_emit(&m, &b, code, 32);
        if (ra != rb || a.ninsns != b.ninsns || hash != candidate_hash()) {
            fprintf(stderr, "emission mismatch trial %u\n", trial); return 1;
        }
    }
    puts("PASS: 20000 original/candidate emissions match (hot/cold code and literals)");
}
