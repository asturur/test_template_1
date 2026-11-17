#!/usr/bin/env python3
"""Audit matched area investigation, warm performance and worst-case contracts."""
import json,gzip,re,hashlib,subprocess
from pathlib import Path
from setup import ROOT,HERE,BASE

def load(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return p.read_text() if p.exists() else gzip.decompress(p.with_suffix(p.suffix+'.gz').read_bytes()).decode()
def fields(line):return {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)}
def rtl(m):return {k:v for k,v in m['source']['files'].items() if k.startswith('rtl/') and Path(k).suffix in ['.v','.sv','.svh']}
def compiler(out,m):
    dat=ROOT/m['executable'];dat=dat.parent/(dat.name+'__verFiles.dat')
    target=out/'compiler-inputs.json'
    if dat.exists():
        names=set(re.findall(r'^S[^\n]*"/work/[^"\n]*/source/(rtl/[^"\n]+)"',dat.read_text(),re.M))
        target.write_text(json.dumps({k:rtl(m)[k] for k in sorted(names)},indent=2)+'\n')
    result=load(target);assert len(result)==51
    return result

def state_bits(text):
    text=re.sub(r"/\*.*?\*/|//[^\n]*",'',text,flags=re.S)
    count=0
    for high,low,names in re.findall(r"\breg\s*(?:\[\s*(\d+)\s*:\s*(\d+)\s*\])?\s*([^;]+);",text):
        width=abs(int(high)-int(low))+1 if high else 1
        for name in names.split(','):
            dimensions=re.findall(r"\[\s*(\d+)\s*:\s*(\d+)\s*\]",name)
            words=1
            for a,b in dimensions:words*=abs(int(a)-int(b))+1
            count+=width*words
    return count

def main():
    cdir=ROOT/'build/sim/spmark-payload/area-frequency-5l-01';ndir=ROOT/'build/sim/spmark-payload/area-banked-5l-02'
    control=load(cdir/'result.json');new=load(ndir/'result.json');assert control['status']==new['status']=='PASS'
    cm=control['manifest'];nm=new['manifest'];cr=rtl(cm);nr=rtl(nm);assert len(cr)==len(nr)==60
    original_bank=subprocess.check_output(['git','show',BASE+':rtl/arm920/tlb_bank.sv'],cwd=ROOT).decode()
    assert state_bits(original_bank)==1744 and state_bits((HERE/'rtl/tlb_bank.sv').read_text())==324
    assert sha(HERE/'rtl/tlb_bank.sv')==nr['rtl/arm920/tlb_bank.sv']
    retained=load(ROOT/'docs/evidence/cpu-late-operand-six-20261117.json')
    assert cr==rtl(retained['manifest'])
    changed=[k for k in cr if cr[k]!=nr[k]]
    assert changed==['rtl/arm/zap_cache.sv','rtl/arm/zap_core.sv','rtl/arm/zap_cp15_cb.sv','rtl/arm/zap_dcache.sv','rtl/arm/zap_top.sv','rtl/arm920/tlb.sv','rtl/arm920/tlb_bank.sv']
    for k in ['programs','payload_sha256','original_rom_sha256','image_id','profiles','repeat']:assert cm[k]==nm[k],k
    comparisons=[];counters={};journals={};whole_run_changes=[]
    for row in new['rows']:
        old=next(x for x in control['rows'] if (x['case'],x['profile'])==(row['case'],row['profile']))
        assert row['oracle']==old['oracle'] and row['deterministic_repeats']==2
        assert row['windows'][2:]==old['windows'][2:]
        assert row['payload_windows']==old['payload_windows']
        whole_run_changes.append(dict(case=row['case'],profile=row['profile'],control=old['total'],candidate=row['total'],added_cycles=row['total']['cycles']-old['total']['cycles']))
        comparisons.append(dict(case=row['case'],profile=row['profile'],control=old['body_cycles_median'],candidate=row['body_cycles_median'],delta=row['body_cycles_median']-old['body_cycles_median']))
        iw,dw=row['profile'].split(':');key=row['case']+' '+row['profile'];pair={}
        for label,d in [('control',cdir),('candidate',ndir)]:
            s=read(d/f'{row["case"]}-{iw}-{dw}-0.log');w=[fields(l) for l in s.splitlines() if l.startswith('TLB_AREA_WINDOW ')];tot=[fields(l) for l in s.splitlines() if l.startswith('TLB_AREA_TOTAL ')];assert len(w)==7 and len(tot)==1
            pair[label]=dict(windows=w,total=tot[0])
        assert pair['control']['windows'][2:]==pair['candidate']['windows'][2:]
        counters[key]=pair;row2=pair['control']['windows'][2]
        row2=dict(row2,exposed_percent=100*row2['union_wait']/row['body_cycles_median'])
        journals[key]=row2
    assert len(new['qualification'])==len(control['qualification'])==6
    # Corrected control row audits. Original full-six/JPEG histograms sampled
    # after hit_vector cleared; retain their valid counts, discard their rows.
    audited_rows={}
    for d,names in [(ROOT/'build/sim/spmark-payload/area-rows-5l-02',['matrix4','triangle_edges']),(ROOT/'build/sim/jpeg-payload/area-rows-jpeg-02',['diffuse_m10_8x8_jpeg'])]:
        result=load(d/'result.json');assert result['status']=='PASS' and rtl(result['manifest'])==cr
        for name in names:
            s=read(d/f'{name}-0-0-0.log');groups=[fields(l) for l in s.splitlines() if l.startswith('TLB_AREA_GROUP index=2 ')];assert len(groups)==16 and all(g['hits']==0 for g in groups if g['row']!=0)
            audited_rows[name]=groups
    jd=ROOT/'build/sim/jpeg-payload/area-banked-jpeg-02';jc=ROOT/'build/sim/jpeg-payload/area-rows-jpeg-02'
    jn=load(jd/'result.json');jb=load(jc/'result.json');assert jn['status']==jb['status']=='PASS' and rtl(jn['manifest'])==nr and rtl(jb['manifest'])==cr
    for a,b in zip(jn['rows'],jb['rows']):
        assert a['memory_profile']==b['memory_profile'] and a['oracle']==b['oracle']
        assert a['observation']['body_cycles_median']==b['observation']['body_cycles_median'] and a['observation']['windows'][2:]==b['observation']['windows'][2:]
        assert {k:v for k,v in a['observation']['total'].items() if k!='cycles'}=={k:v for k,v in b['observation']['total'].items() if k!='cycles'}
        s=read(jc/f'{a["case"]}-{a["memory_profile"].replace(":","-")}-0.log');w=[fields(l) for l in s.splitlines() if l.startswith('TLB_AREA_WINDOW ')];journals[a['case']+' '+a['memory_profile']]=w[2]
    sd=ROOT/'build/sim/tlb-area/area-banked-span-02';span=load(sd/'result.json');assert span['status']=='PASS' and rtl(span['manifest'])==nr
    sb=load(ROOT/'build/sim/cpu-late-operand/step5l-03/result.json');scomp=[]
    for row in span['rows']:
        old=next(x for x in sb['rows'] if (x['case'],x['profile'])==(row['case'],row['profile']))
        assert row['cycles']==old['cycles'] and row['windows'][2:]==old['windows'][2:]
        assert span['oracle'][row['case']]==sb['oracle'][row['case']]
        scomp.append(dict(case=row['case'],profile=row['profile'],cycles=row['cycles']))
    assert span['programs']=={k:v for k,v in sb['programs'].items() if k in span['programs']}
    units=load(ROOT/'build/sim/tlb-area/banked-units-05/result.json');assert units['status']=='PASS' and units['strict_verilog_2001'] and {k:v for k,v in units['source']['files'].items() if k in nr}==nr
    eq=load(ROOT/'build/sim/tlb-area/banked-equivalence-03/result.json');assert eq['status']=='PASS' and eq['truncated_capacity_rejected']
    dc=load(ROOT/'build/sim/tlb-area/area-control-diagnostics-01/result.json');dn=load(ROOT/'build/sim/tlb-area/area-banked-diagnostics-03/result.json');assert dc['status']==dn['status']=='PASS'
    diagnostics=[]
    for old,row in zip(dc['rows'],dn['rows']):
        assert old['name']==row['name'] and old['rom_sha256']==row['rom_sha256'] and old['status']==row['status']
        diagnostics.append(dict(case=old['name'],control=old['cycles'],candidate=row['cycles'],delta=row['cycles']-old['cycles'],percent=100*(row['cycles']/old['cycles']-1)))
    core=load(ROOT/'build/sim/tlb-area/area-banked-core-04/result.json');safety=load(sd/'safety.json');assert core['status']==safety['status']=='PASS' and {k:v for k,v in core['source']['files'].items() if k in nr}==nr
    # Fitter direct rows are independent leaves; never add parents to children.
    fit=ROOT/'build/fit/combined-5jk-20261117/quartus-logs-44123116917/output_files/Template.fit.rpt';resources=[]
    for l in fit.read_text(errors='replace').splitlines():
        f=[x.strip() for x in l.split(';')[1:-1]]
        if len(f)==17 and f[-2] in ['arm920_tlb_bank','arm920_cache_tags','ngage_mmc_card']:
            resources.append(dict(entity=f[-2],path=f[14],ALMs_subtree=float(f[1].split()[0]),ALMs_direct=float(re.search(r'\(([^)]+)\)',f[1])[1]),registers=f[7],M10Ks_subtree=int(f[10]),block_bits_subtree=int(f[9])))
    assert len(resources)==5
    summary=load(ROOT/'build/fit/combined-5jk-20261117/summary.json')
    baseline=dict(fit_commit=BASE,fit_run='44123116917',report_sha256=sha(fit),resources=summary['resources'],nodes=resources,ALM_capacity=41910,M10K_capacity=553,LAB_capacity=4191)
    assert abs(sum(x['ALMs_direct'] for x in resources if x['entity']=='arm920_tlb_bank')-4095.9)<.01
    # Pin compiler closures before disposing generated objects.
    compiled={'control':compiler(cdir,cm),'candidate':compiler(ndir,nm),'span':compiler(sd,span['manifest'])}
    # JPEG manifests do not record an executable path; retain it independently.
    for label,d,m in [('jpeg_control',jc,jb['manifest']),('jpeg_candidate',jd,jn['manifest'])]:
        exe=d/'obj/Vbench';p=d/'compiler-inputs.json'
        if exe.exists():
            dat=exe.parent/'Vbench__verFiles.dat';names=set(re.findall(r'^S[^\n]*"/work/[^"\n]*/source/(rtl/[^"\n]+)"',dat.read_text(),re.M));p.write_text(json.dumps(dict(executable_sha256=sha(exe),inputs={k:rtl(m)[k] for k in sorted(names)}),indent=2)+'\n')
        compiled[label]=load(p);assert len(compiled[label]['inputs'])==51
    production=load(ROOT/'build/fit/combined-5jk-20261117/qualification.json')['compiled_RTL_sha256']
    assert len(production)==60 and all(sha(ROOT/k)==v for k,v in production.items())
    assert sha(ROOT/'rtl/ngage_mmc_card.v')==summary['source']['compiled_source_sha256']['rtl/ngage_mmc_card.v']
    receipt=dict(production_source_unchanged=True,status='PASS',decision='Retain isolated banked TLB area candidate for matched physical fit; no production promotion or measured ALM claim',baseline=baseline,control_manifest=cm,candidate_manifest=nm,changed_from_5L=changed,workloads=comparisons,whole_run_changes=whole_run_changes,counters=counters,scored_windows=journals,corrected_row_audits=audited_rows,jpeg=jn,jpeg_whole_run_changes=[dict(profile=a['memory_profile'],added_cycles=a['observation']['total']['cycles']-b['observation']['total']['cycles']) for a,b in zip(jn['rows'],jb['rows'])],span_and_stream=scomp,unit_tests=units,equivalence=eq,diagnostic_costs=diagnostics,core_stimulus_checks=core,diagnostic_builds=dict(control=dc['rows'][0]['simulator_build'],candidate=dn['rows'][0]['simulator_build']),safety=safety,compiler_inputs=compiled,source_bits_per_bank=dict(original=1744,candidate=324,delta=-1420),physical_estimates=dict(label='planning only; not fitted',ALMs_saved_total=[1000,2500],M10Ks_additional=[10,16],M10Ks_total=[512,518],M10Ks_remaining=[35,41],register_fitted_delta=None,LAB_fitted_delta=None,timing=None),physical_fit_performed=False,row_observer_correction='Initial group counter sampled default selected_entry after hit_vector cleared. Counts/exposure valid; initial groups excluded. Corrected registered-row audits pass and candidate uses corrected observer.',driver_inputs={str(p.relative_to(ROOT)):sha(p) for p in HERE.rglob('*') if p.is_file() and p.suffix in ['.py','.sv','.vh']})
    target=ROOT/'docs/evidence/tlb-area-20261117.json';target.write_text(json.dumps(receipt,indent=2)+'\n');print('PASS area prototype: matched real work unchanged, capacity/mutation equivalence, diagnostic costs, resources kept separate')
if __name__=='__main__':main()
