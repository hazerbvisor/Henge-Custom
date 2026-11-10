#include "machine.h"
#include "memop.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern int reference_vmem_xfer(HvCpu *,uint64_t,void *,uint32_t,int,int,uint64_t);
static HvMachine m;
static HvCpu cpu;
static unsigned char *ram;
static uint64_t *pt;
typedef struct { uint64_t off,val,size,write; } Event;
static Event events[32];
static unsigned nevents;
static uint64_t read_device(void *unused,uint64_t off,unsigned size) {
    (void)unused;
    uint64_t value=off*0x0101010101010101ull+size;
    if(nevents>=32) abort();
    events[nevents++]=(Event){off,value,size,0};return value;
}
static void write_device(void *unused,uint64_t off,uint64_t value,unsigned size) {
    (void)unused;
    if(nevents>=32) abort();
    events[nevents++]=(Event){off,value,size,1};
}
typedef struct {
    uint64_t pc,esr,far,elr,el,reason;
    int rc;
    unsigned count;
    unsigned char out[128],memory[32768];
    Event events[32];
} Result;
static Result results[2];
static void compare(uint64_t va,unsigned len,int write,int mmu,int el,int readonly,int stats) {
    for(unsigned candidate=0;candidate<2;candidate++) {
        Result *r=&results[candidate];memset(r,0,sizeof *r);
        memset(r->out,0x5a,sizeof r->out);
        for(unsigned i=0;i<32768;i++) ram[i]=(unsigned char)(i*13);
        m.ram[0].readonly=readonly;m.stats_interval=stats;nevents=0;
        memset(events,0,sizeof events);
        hv_cpu_reset(&cpu,&m);
        if(mmu) {
            cpu.mair_el1=0xff;cpu.ttbr0_el1=0x80000000;
            cpu.tcr_el1=16|(2u<<14)|(1u<<23)|(5ull<<32);
            cpu.sctlr_el1|=1|(1u<<2)|(1u<<12);
        }
        r->rc=candidate?hv_vmem_xfer(&cpu,va,r->out,len,write,el,0x1000):
                        reference_vmem_xfer(&cpu,va,r->out,len,write,el,0x1000);
        r->pc=cpu.pc;r->esr=cpu.esr_el1;r->far=cpu.far_el1;r->elr=cpu.elr_el1;
        r->el=cpu.el;r->reason=cpu.exit_reason;r->count=nevents;
        memcpy(r->memory,ram,sizeof r->memory);memcpy(r->events,events,sizeof events);
    }
    if(memcmp(&results[0],&results[1],sizeof(Result))) {
        fprintf(stderr,"transfer mismatch va=%llx len=%u write=%d MMU=%d EL=%d ROM=%d stats=%d\n",
                (unsigned long long)va,len,write,mmu,el,readonly,stats);exit(1);
    }
}
int main(void) {
    if(hv_machine_init(&m,1<<20)) return 1;
    ram=aligned_alloc(16384,32768);pt=aligned_alloc(16384,65536);
    if(!ram||!pt||hv_machine_add_ram(&m,0x40000000,32768,ram,0)||
       hv_machine_add_ram(&m,0x80000000,65536,pt,0)||
       hv_machine_add_mmio(&m,0x40010000,32,NULL,read_device,write_device,"fixture")) return 1;
    memset(pt,0,65536);pt[0]=0x80004000|3;pt[2048]=0x80008000|3;
    pt[4096+32]=0x40000000|1|(3u<<8)|(1u<<10);
    const uint64_t addresses[]={0x40000000,0x40000ffc,0x40003ffc,0x40007ffc,
                              0x40010000,0x40010018,0x40020000,0x50000000};
    const unsigned lengths[]={0,1,4,8,16,64};
    unsigned checks=0;
    for(unsigned a=0;a<8;a++) for(unsigned l=0;l<6;l++)
    for(int write=0;write<2;write++) for(int mmu=0;mmu<2;mmu++)
    for(int el=0;el<2;el++) for(int rom=0;rom<2;rom++) for(int stats=0;stats<2;stats++) {
        compare(addresses[a],lengths[l],write,mmu,el,rom,stats?10:0);checks++;
    }
    printf("PASS: %u original/candidate transfers: RAM, ROM writes, MMIO order, permission faults, unmapped ranges and page edges\n",checks);
    return 0;
}
