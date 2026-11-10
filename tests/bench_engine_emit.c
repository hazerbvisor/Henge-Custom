/* Same-process, alternating short batches. Emission only, no guest execution. */
#include "translate.h"
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
extern int reference_emit(HvMachine *,HvBlock *,const uint32_t *,uint32_t);
extern uint32_t reference_words(void);
static uint32_t rng=1;
static uint32_t next(void) { rng^=rng<<13;rng^=rng>>17;return rng^=rng<<5; }
int main(void) {
    static HvMachine m;
    static uint32_t code[4096][32];
    const uint32_t ops[]={0x91000400,0x8b020021,0xf9400020,0xf9000420,0xd503201f,0xa9400c22};
    const char *names[]={"mixed","alu","memory"};
    mach_timebase_info_data_t tb;mach_timebase_info(&tb);
    for(unsigned shape=0;shape<3;shape++) {
        for(unsigned k=0;k<4096;k++) {
            for(unsigned i=0;i<31;i++)
                code[k][i]=shape==0?ops[(i+k)%6]:shape==1?0x91000000|(next()&0x003fffff):0xf9400000|(next()&0x003fffff);
            code[k][31]=0xd65f03c0;
        }
        for(unsigned round=0;round<10;round++) {
            uint64_t ticks[2]={0},sum[2]={0};
            for(unsigned batch=0;batch<128;batch++) for(unsigned order=0;order<2;order++) {
                unsigned candidate=(order+batch+round)&1;
                uint64_t start=mach_absolute_time();
                for(unsigned i=0;i<256;i++) {
                    HvBlock b={.va=0x100000,.pa=0x100000};m.nslots=0;
                    const uint32_t *words=code[(batch*256+i)&4095];
                    int rc=candidate?hv_translate_emit(&m,&b,words,32):reference_emit(&m,&b,words,32);
                    if(rc) abort();
                    sum[candidate]+=b.ninsns+(candidate?hv_translate_last_words():reference_words());
                }
                ticks[candidate]+=mach_absolute_time()-start;
            }
            if(sum[0]!=sum[1]) abort();
            if(round) printf("{\"scenario\":\"%s\",\"round\":%u,\"baseline_ms\":%.6f,\"candidate_ms\":%.6f,\"checksum\":%llu}\n",
                names[shape],round,ticks[0]*(double)tb.numer/tb.denom/1e6,ticks[1]*(double)tb.numer/tb.denom/1e6,(unsigned long long)sum[0]);
        }
    }
}
