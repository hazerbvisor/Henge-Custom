#ifndef HENGE_SCRATCH_H
#define HENGE_SCRATCH_H
#include <stdint.h>

/* Same priority as the translator's original register list: free scratch,
   then x9..x14, then the remaining borrowable registers in ascending order.
   x18, x28 and SP/XZR are never borrowed. ctz is called only for nonzero input. */
static inline int hv_pick_scratch(uint32_t *used) {
    uint32_t available = ~*used & ((1u << 6) | (1u << 7) | (1u << 15));
    if (!available) available = ~*used & 0x00007e00u;
    if (!available) available = ~*used & 0x6ffbffffu;
    if (!available) return -1;
    int reg = __builtin_ctz(available);
    *used |= 1u << reg;
    return reg;
}
#endif
