#!/usr/bin/env python3
"""Complete5F regression assessment after disposable old build outputs retire."""
from pathlib import Path
import argparse,gzip,hashlib,json,subprocess,shutil
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('--jpeg',type=Path,required=True);p.add_argument('--cpu',type=Path,required=True);a=p.parse_args()
load=lambda p:json.loads(p.read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
base='fae40167654949f9530e75eecd6d58c4fc74d013'
original=subprocess.check_output(['git','show',base+':docs/evidence/cpu-store-postindex-20261117.json'],cwd=ROOT)
saved=json.loads(original);assert saved['status']=='PASS'
jpeg=ROOT/a.jpeg;cpu=ROOT/a.cpu
assert jpeg.resolve().parent==ROOT/'build/sim/jpeg-payload' and jpeg.name.startswith('postindex-jpeg-')
assert cpu.resolve().parent==ROOT/'build/sim/cpu-store-postindex' and cpu.name.startswith('diagnostics-')
j=load(jpeg/'result.json');m=load(jpeg/'manifest.json');d=load(cpu/'result.json')
assert j['status']==d['status']=='PASS'
assert m['source']['source_id']==d['source_id']==saved['candidate_source_id']
compiled={n:h for n,h in m['source']['files'].items() if n.startswith('rtl/') and Path(n).suffix in ['.v','.sv','.svh']}
assert len(compiled)==60
for n,h in compiled.items():
 assert sha(ROOT/n)==sha(jpeg/'source'/n)==sha(cpu/'source'/n)==h,n
old=ROOT/'build/sim/jpeg-payload/paired-jpeg-01'
oldm=load(old/'manifest.json');oldj=load(old/'result.json');assert oldj['status']=='PASS'
assert [n for n,h in compiled.items() if oldm['source']['files'][n]!=h]==['rtl/arm/zap_predecode_main.sv']
for k in ['image_id','harness_sha256','observer_sha256','programs','rom_sha256','payload_sha256']:
 assert m[k]==oldm[k],k
assert [r['memory_profile'] for r in j['rows']]==['0:0','2:9']
rows=[]
for before,after in zip(oldj['rows'],j['rows']):
 assert before['oracle']==after['oracle']
 # Untimed ARM setup/check loops also use post-index stores. Their whole-run
 # totals can improve; require exact original scored windows, not setup time.
 assert before['observation']['windows'][2:]==after['observation']['windows'][2:]
 obs=after['observation'];assert obs['body_cycles_median']==84353
 assert len(obs['windows'])==7 and all(w['retire_proxy']==22508 for w in obs['windows'])
 case=after['case'];ps=after['memory_profile'].replace(':','-')
 for repeat in range(2):assert (jpeg/f'{case}-{ps}-{repeat}.log').exists()
 rows.append(dict(profile=after['memory_profile'],median=84353,scored=[w['cycles'] for w in obs['windows'][2:]],
                  exact_5D_scored_window_match=True,original_oracle_match=True,
                  control_whole_run=before['observation']['total'],candidate_whole_run=obs['total']))
negative=jpeg/'diffuse_m10_8x8_jpeg-wrong-output.log'
assert 'guest result check failed' in negative.read_text()
assert len(d['rows'])==8
assert sum(r['status']=='pass' for r in d['rows'])==6
assert sum(r['status']=='unmapped_access' and r['blocked_address']==0x0bad0000 for r in d['rows'])==2
exe=cpu/'obj/Vngage_cpu_sim';binary=load(cpu/'obj/ngage-build-manifest.json')
assert sha(exe)==binary['binary_sha256']
record=dict(status='PASS',accepted_commit=base,candidate_source_id=saved['candidate_source_id'],
 simulator_image_id=m['image_id'],docker_recovery='User-authorized restart; normal stop timed out, supported force-stop/start recovered the identical installed image.',
 original_5F_evidence_sha256=hashlib.sha256(original).hexdigest(),original_required_checks='PASS; retained immutable accepted receipt',
 compiled_RTL_inputs=60,current_RTL_matches_exact_measured_candidate=True,jpeg=rows,
 jpeg_wrong_output='EXPECTED_FAILURE',jpeg_negative_sha256=sha(negative),jpeg_executable_sha256=sha(jpeg/'obj/Vbench'),
 jpeg_result_sha256=sha(jpeg/'result.json'),cpu_result_sha256=sha(cpu/'result.json'),cpu_executable_sha256=sha(exe),
 cpu_diagnostics=d['rows'],compiled_RTL_sha256=compiled,cpu_build_manifest=binary,
 diagnostic_guest_sha256={n:sha(ROOT/'sim/programs'/n) for n in ['smoke.S','mmu_fcse.S','prefetch_fault.S','btb_return.S','common.inc','link.ld']},
 artifacts=dict(jpeg=str(a.jpeg),cpu=str(a.cpu)),
 decision='Retain5F. JPEG unchanged84353 in both profiles and eight real-CPU ARM/Thumb/link/FCSE/prefetch-fault/return-alias checks pass. No RTL change.',
 physical_fit_or_hardware=False,
 retired_build_directories=[str(p.relative_to(ROOT)) for run in [jpeg,cpu] for p in [run/'obj',run/'source']])
target=ROOT/'docs/evidence/cpu-store-postindex-recovery-20261117.json'
target.write_text(json.dumps(record,indent=2)+'\n')
for run in [jpeg,cpu]:
 # Hashes/results are durable; frozen inputs regenerate from the pinned Git
 # source and maintained private fixtures. No active run uses these trees.
 for directory in ['obj','source']:
  shutil.rmtree(run/directory)
 for f in run.rglob('*'):
  if not f.is_file():continue
  if f.suffix in ['.o','.elf','.bin','.hex']:
   f.unlink()
  elif f.suffix in ['.log','.tsv'] and f.stat().st_size>100000:
   raw=f.read_bytes();f.with_suffix(f.suffix+'.gz').write_bytes(gzip.compress(raw));f.unlink()
print('PASS recovered5F: exact5D JPEG observation/oracle match,84353 both profiles;8CPU diagnostics;60RTL hashes unchanged',target)
