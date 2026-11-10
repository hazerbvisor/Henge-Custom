#include "machine.h"
#include "memop.h"
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern int reference_vmem_xfer(HvCpu *,uint64_t,void *,uint32_t,int,int,uint64_t);
int main(void) {
    static HvMachine m;
    static HvCpu cpu;
    if(hv_machine_init(&m,1<<20)) return 1;
    unsigned char *ram=aligned_alloc(16384,32768);
    if(!ram || hv_machine_add_ram(&m,0x40000000,32768,ram,0)) return 1;
    for(unsigned i=0;i<32768;i++) ram[i]=(unsigned char)(i*13);
    uint64_t *pt=aligned_alloc(16384,65536);
    if(!pt || hv_machine_add_ram(&m,0x80000000,65536,pt,0)) return 1;
    memset(pt,0,65536);
    pt[0]=0x80004000|3;
    pt[2048]=0x80008000|3;
    pt[4096+32]=0x40000000|1|(3u<<8)|(1u<<10); /* 32 MiB identity block */
    hv_cpu_reset(&cpu,&m);
    cpu.mair_el1=0xff;
    cpu.ttbr0_el1=0x80000000;
    cpu.tcr_el1=16|(2u<<14)|(1u<<23)|(5ull<<32);
    cpu.sctlr_el1|=1|(1u<<2)|(1u<<12);
    m.stats_interval=getenv("HV_BENCH_STATS")?10:0;
    static unsigned char out[4096];
    const unsigned lens[]={8,64,4096,8,8,64};
    const char *names[]={"read8","read64","read4096","cross-page","write8-control","write64-control"};
    mach_timebase_info_data_t tb;mach_timebase_info(&tb);
    for(unsigned scenario=0;scenario<6;scenario++) for(unsigned round=0;round<10;round++) {
        uint64_t ticks[2]={0},checksum[2]={0};
        uint64_t va=0x40000000+(scenario==3?4092:128);
        unsigned len=lens[scenario];
        int write=scenario>=4;
        for(unsigned batch=0;batch<128;batch++) for(unsigned order=0;order<2;order++) {
            unsigned candidate=(order+batch+round)&1;
            uint64_t start=mach_absolute_time();
            for(unsigned i=0;i<1024;i++) {
                int rc=candidate?hv_vmem_xfer(&cpu,va,out,len,write,1,0x1000):reference_vmem_xfer(&cpu,va,out,len,write,1,0x1000);
                if(rc) abort();
                checksum[candidate]+=out[0];
            }
            ticks[candidate]+=mach_absolute_time()-start;
            if(memcmp(out,ram+(va-0x40000000),len)) abort();
        }
        if(checksum[0]!=checksum[1]) abort();
        if(round) printf("{\"scenario\":\"%s\",\"round\":%u,\"baseline_ms\":%.6f,\"candidate_ms\":%.6f,\"checksum\":%llu}\n",
            names[scenario],round,ticks[0]*(double)tb.numer/tb.denom/1e6,ticks[1]*(double)tb.numer/tb.denom/1e6,(unsigned long long)checksum[0]);
    }
    return 0;
}
