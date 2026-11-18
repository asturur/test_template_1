from pathlib import Path
import sys,json,subprocess,re,argparse
ROOT=Path(__file__).resolve().parents[3];sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
import run as common
from workload import cases
P=Path(__file__).resolve().parent;parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,default=ROOT/'build/sim/jpeg-payload/error-diffusion-20261115-v2');args=parser.parse_args();O=args.base.resolve();O.relative_to(ROOT)
r=json.loads((O/'result.json').read_text());assert r['status']=='PASS'
bench=common.support();old=O/'source-pre-store';oldmanifest=bench.snapshot(old,revision='d4f2a8');common.save(O/'pre-store-source.json',oldmanifest)
allfiles=[]
for name in ['rtl/ngage_cpu.sv','rtl/ngage_bram.v']:allfiles.append(name)
for folder in ['rtl/arm','rtl/arm920']:allfiles += [str(p.relative_to(O/'source')) for p in sorted((O/'source'/folder).iterdir()) if p.suffix in ('.v','.sv')]
diff=[name for name in allfiles if common.sha((old/name).read_bytes())!=common.sha((O/'source'/name).read_bytes())];assert diff==['rtl/arm920/cache_access.sv'],diff
original={(x['case'],x['memory_profile']):x['observation'] for x in r['rows']};docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint'];image=common.IMAGE
out=dict(status='INCOMPLETE',compiled_source_changes=diff,rows=[],original_code_retirement_matches=True)
common.save(O/'qualification.json',out)
try:
 for name,source,tb in [('unprofiled',O/'source',O/'tb-base.v'),('pre-store',old,O/'tb.v')]:
  rtl=[source/n for n in allfiles]
  common.command(docker+['verilator',image,'--binary','--timing','--assert','-j','3','-Wno-fatal','-Wno-lint','-DNGAGE_RUNTIME_TRACE','-DBENCH_HAS_LINE','-GLINE_ENABLE=1','--top-module','bench','--Mdir',common.cpath(O/('obj-'+name)),'-I'+common.cpath(source/'rtl/arm'),'-I'+common.cpath(O)]+[common.cpath(p) for p in rtl]+[common.cpath(tb)],O/(name+'-build.log'))
  for c in cases():
   for profile in ('0:0','2:9'):
    iw,dw=profile.split(':');observations=[]
    for repeat in range(1 if name=='unprofiled' else 2):
     sy=r['manifest']['programs'][c['id']];log=O/f'{name}-{c["id"]}-{iw}-{dw}-{repeat}.log'
     common.command(docker+[common.cpath(O/('obj-'+name)/'Vbench'),image,'+program='+common.cpath(O/(c['id']+'.hex')),'+payload='+common.cpath(O/'ROM505.hex'),'+firmware='+common.cpath(O/'firmware.hex'),f'+begin_pc={sy["body_begin"]:x}',f'+end_pc={sy["body_end"]:x}',f'+i_wait={iw}',f'+d_wait={dw}','+max_cycles=12000000','+ngage-compact-trace'],log)
     text=log.read_text();ob=bench.parse_log(text,c);counts=[dict(re.findall(r'(\w+)=(\d+)',l)) for l in text.splitlines() if l.startswith('PAYLOAD_WINDOW ')];assert len(counts)==7
     expected_instructions=next(t for t in r['rows'] if t['case']==c['id'])['oracle']['instructions']
     assert all(int(x['payload_retire_proxy'])==expected_instructions and int(x['helper_retire_proxy'])==0 for x in counts),'original code count mismatch'
     if name=='unprofiled':assert ob==original[c['id'],profile],'observer perturbed raw counters'
     observations.append(ob)
    assert all(o==observations[0] for o in observations),'repeat differs'
    row=dict(variant=name,case=c['id'],profile=profile,observation=observations[0]);out['rows'].append(row);common.save(O/'qualification.json',out);print('PASS',name,c['id'],profile,observations[0]['body_cycles_median'],flush=True)
 out['status']='PASS';common.save(O/'qualification.json',out)
except Exception as exc:
 out.update(status='FAIL',error=str(exc));common.save(O/'qualification.json',out);raise
