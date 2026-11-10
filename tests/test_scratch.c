#include "scratch.h"
#include <stdio.h>
#include <stdlib.h>

static int original(uint32_t *used) {
    static const unsigned char priority[] = {6,7,15,9,10,11,12,13,14,0,1,2,3,4,5,8,16,17,19,20,21,22,23,24,25,26,27,29,30};
    for (unsigned i=0;i<sizeof priority;i++) {
        unsigned reg=priority[i];
        if (!(*used & (1u<<reg))) { *used |= 1u<<reg; return (int)reg; }
    }
    return -1;
}
static void check(uint32_t initial) {
    uint32_t a=initial,b=initial;
    for (unsigned step=0;step<32;step++) {
        int x=original(&a),y=hv_pick_scratch(&b);
        if (x!=y || a!=b) {
            fprintf(stderr,"scratch mismatch %08x step %u\n",initial,step);exit(1);
        }
    }
}
int main(void) {
    check(0);check(~0u);
    for (unsigned i=0;i<32;i++) { check(1u<<i);check(~(1u<<i)); }
    uint32_t rng=1;
    for (unsigned i=0;i<1000000;i++) {
        rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;check(rng);
    }
    puts("PASS: scratch priority, state updates, exhaustion and 1000000 random masks");
}
