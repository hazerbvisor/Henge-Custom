#!/usr/bin/env python3
"""Compare the current translator to a pinned Git revision without guest disks."""
import ast
import json
import platform
import statistics
import subprocess
from pathlib import Path
import sys

root=Path(__file__).resolve().parents[1]
baseline=sys.argv[1] if len(sys.argv)>1 else 'a96b4b57abd5b0343a544135de7f85619c474519'
build=Path('build/engine-perf')
def run(args,**kw): return subprocess.run(args,cwd=root,check=True,**kw)
run(['make','-j2','B='+str(build),str(build/'test_bench')],stdout=subprocess.DEVNULL)
original=subprocess.check_output(['git','show',baseline+':core/translate.c'],cwd=root,text=True)
# Reuse the byte-snapshot helper used by the existing emitter equivalence test.
tree=ast.parse((root/'tools/check_translation.py').read_text())
suffix=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign)
            and any(isinstance(t,ast.Name) and t.id=='suffix' for t in n.targets))
renames={'hv_translate_emit':'reference_emit','hv_translate_place':'reference_place',
         'hv_translate_block':'reference_block','hv_translate_last_words':'reference_words',
         'hv_branch_retarget':'reference_retarget'}
flags=['-std=c11','-O2','-g','-Icore','-Ihost']
for name,text in [('reference',original),('candidate',(root/'core/translate.c').read_text())]:
    source=build/(name+'-verify.c')
    (root/source).write_text(text+suffix.replace('HASH_NAME',name+'_hash'))
    defines=['-D'+k+'='+v for k,v in renames.items()] if name=='reference' else []
    run(['clang',*flags,*defines,'-c',str(source),'-o',str(build/(name+'-verify.o'))])
objects=[str(build/(n+'.o')) for n in ['classify','operands','dispatch','mmu','memop',
          'exception','sysreg','machine','jit_region','enter','disk','reference-verify','candidate-verify']]
for test in ['verify_emit','bench_engine_emit']:
    run(['clang',*flags,'tests/'+test+'.c',*objects,'-o',str(build/test)])
run([str(build/'verify_emit')])
output=subprocess.check_output([str(build/'bench_engine_emit')],cwd=root,text=True)
samples=[json.loads(line) for line in output.splitlines()]
summary={}
for scenario in sorted({s['scenario'] for s in samples}):
    subset=[s for s in samples if s['scenario']==scenario]
    summary[scenario]={
        'baseline_median_ms':statistics.median(s['baseline_ms'] for s in subset),
        'candidate_median_ms':statistics.median(s['candidate_ms'] for s in subset),
        'paired_median_improvement_pct':statistics.median(100*(1-s['candidate_ms']/s['baseline_ms']) for s in subset),
        'improved_pairs':sum(s['candidate_ms']<s['baseline_ms'] for s in subset),
        'pairs':len(subset)}
report={'baseline':baseline,'host':platform.platform(),'scope':'synthetic emission only; no game FPS claim',
        'samples':samples,'summary':summary}
(root/build/'comparison.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(summary,indent=2))
