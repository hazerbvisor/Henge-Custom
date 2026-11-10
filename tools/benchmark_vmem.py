#!/usr/bin/env python3
"""Paired RAM slow-read benchmarks and write controls with the software MMU on."""
import json
import os
import argparse
import platform
import statistics
import subprocess
from pathlib import Path

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('baseline',nargs='?',default='eaf01e9ea5c6e6cc97504c1e609c86f59697449c')
parser.add_argument('--check-only',action='store_true')
args=parser.parse_args()
baseline=args.baseline
b=Path('build/vmem-perf')
def run(args,**kwargs): return subprocess.run(args,cwd=root,check=True,**kwargs)
run(['make','-j2','B='+str(b),str(b/'test_bench')],stdout=subprocess.DEVNULL)
original=subprocess.check_output(['git','show',baseline+':core/memop.c'],cwd=root,text=True)
(root/b/'baseline-memop.c').write_text(original)
flags=['-std=c11','-O2','-g','-Icore','-Ihost']
defines=['-Dhv_vmem_xfer=reference_vmem_xfer','-Dhv_mem_decode=reference_mem_decode','-Dhv_mem_emulate=reference_mem_emulate']
run(['clang',*flags,*defines,'-c',str(b/'baseline-memop.c'),'-o',str(b/'reference-memop.o')])
objects=[str(b/(name+'.o')) for name in ['classify','operands','translate','dispatch','mmu','memop','exception','sysreg','machine','jit_region','enter','disk','reference-memop']]
for test in ['test_vmem_equivalence','bench_vmem_read']:
    run(['clang',*flags,'tests/'+test+'.c',*objects,'-o',str(b/test)])
run([str(b/'test_vmem_equivalence')])
if args.check_only:
    raise SystemExit(0)
output=subprocess.check_output([str(b/'bench_vmem_read')],cwd=root,text=True)
samples=[json.loads(line) for line in output.splitlines()]
summary={}
for scenario in sorted({s['scenario'] for s in samples}):
    subset=[s for s in samples if s['scenario']==scenario]
    summary[scenario]={'baseline_median_ms':statistics.median(s['baseline_ms'] for s in subset),
                       'candidate_median_ms':statistics.median(s['candidate_ms'] for s in subset),
                       'paired_median_improvement_pct':statistics.median(100*(1-s['candidate_ms']/s['baseline_ms']) for s in subset),
                       'improved_pairs':sum(s['candidate_ms']<s['baseline_ms'] for s in subset),'pairs':len(subset)}
report={'baseline':baseline,'host':platform.platform(),'stats_enabled':bool(os.getenv('HV_BENCH_STATS')),'scope':'software MMU enabled, RAM slow-read helper and write controls; not end-to-end game performance',
        'samples':samples,'summary':summary}
(root/b/'comparison.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(summary,indent=2))
