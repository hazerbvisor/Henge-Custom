import json, subprocess, sys
from pathlib import Path
root=Path(sys.argv[1]).resolve()
def run(args, **kw): return subprocess.run(args,cwd=root,check=True,**kw)
b='build/translation-check'
targets=['classify','operands','jit_region','jit','mem','mmu','exc','bench']
(root/'build').mkdir(exist_ok=True)
(root.parent/'artifacts').mkdir(exist_ok=True)
original_path='    int stolen[4] = {-1, -1, -1, -1}; /* per field: the guest register to rename, or -1 */\n    uint32_t used = 0;\n    int any = 0;\n    for (int f = 0; f < 4; f++) {\n        if (!(fields & (1u << f))) continue;\n        int r = hv_field_reg(insn, f);\n        used |= 1u << r;\n        if (is_stolen(r)) { /* guest SP is the host SP while blocks run: copied as it is */\n            stolen[f] = r;\n            any = 1;\n        }\n    }\n    if (!any) {\n        put(e, insn);\n        return;\n    }\n'
candidate_path='    /* Decode register fields once, using constant shifts. Most copied\n       instructions use no stolen registers and need no renaming array. */\n    uint32_t used = ((fields & HV_FIELD_RD) ? 1u << (insn & 31) : 0) |\n                    ((fields & HV_FIELD_RN) ? 1u << ((insn >> 5) & 31) : 0) |\n                    ((fields & HV_FIELD_RM) ? 1u << ((insn >> 16) & 31) : 0) |\n                    ((fields & HV_FIELD_RA) ? 1u << ((insn >> 10) & 31) : 0);\n    const uint32_t stolen_mask = (1u << 6) | (1u << 7) | (1u << 15) | (1u << 18) | (1u << 28);\n    if (!(used & stolen_mask)) {\n        put(e, insn);\n        return;\n    }\n    int stolen[4] = {-1, -1, -1, -1};\n    for (int f = 0; f < 4; f++) {\n        if (!(fields & (1u << f))) continue;\n        int r = hv_field_reg(insn, f);\n        if (is_stolen(r)) stolen[f] = r;\n    }\n'
source=(root/'core/translate.c').read_text()
assert source.count(candidate_path)==1
(root/'build/translation-original.c').write_text(source.replace(candidate_path,original_path,1))
run(['make','B='+b,'CC=clang -Wl,-stack_size,0x4000000',*[b+'/test_'+n for n in targets]])
for n in targets: run([b+'/test_'+n])
objects=[b+'/'+n+'.o' for n in ['classify','operands','dispatch','mmu','memop','exception','sysreg','machine','jit_region','enter','disk']]
flags=['-std=c11','-O2','-Icore','-Ihost']
suffix='''
uint64_t HASH_NAME(void) {
 uint64_t h=1469598103934665603ull;
 for(unsigned part=0;part<3;part++) {
  const unsigned char *data=part==0?(const void*)E.hot:part==1?(const void*)E.cold:(const void*)E.pool;
  unsigned size=part==0?E.nhot*4:part==1?(E.flat?0:E.pool_at*4):E.npool*8;
  if(part==0 && E.flat) size=E.pool_at*4;
  for(unsigned i=0;i<size;i++) h=(h^data[i])*1099511628211ull;
 }
 return h;
}
'''
renames={'hv_translate_emit':'reference_emit','hv_translate_place':'reference_place','hv_translate_block':'reference_block','hv_translate_last_words':'reference_words','hv_branch_retarget':'reference_retarget'}
for name,src in [('reference','build/translation-original.c'),('candidate','core/translate.c')]:
 p=root/b/(name+'-verify.c');p.write_text((root/src).read_text()+suffix.replace('HASH_NAME',name+'_hash'))
 defs=['-D'+k+'='+v for k,v in renames.items()] if name=='reference' else []
 run(['clang',*flags,*defs,'-c',str(p),'-o',b+'/'+name+'-verify.o'])
run(['clang',*flags,'tests/verify_emit.c',*objects,b+'/reference-verify.o',b+'/candidate-verify.o','-o',b+'/verify_emit'])
run([b+'/verify_emit'])
run(['clang',*flags,'-c','build/translation-original.c','-o',b+'/baseline.o'])
for name,obj in [('baseline','baseline.o'),('candidate','translate.o')]:
 run(['clang',*flags,'tests/bench_translate.c',*objects,b+'/'+obj,'-o',b+'/emission-'+name])
results=[]
for round in range(7):
 for name in (['baseline','candidate'] if round%2==0 else ['candidate','baseline']):
  p=subprocess.run([b+'/emission-'+name],cwd=root,check=True,text=True,capture_output=True)
  results.append(dict(round=round,build=name,output=p.stdout))
(root.parent/'artifacts/translation-emission.json').write_text(json.dumps(results,indent=2))
print('PASS: translation regressions, original/candidate emission equivalence, and paired synthetic benchmarks')
