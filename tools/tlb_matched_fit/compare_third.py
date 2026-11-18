"""Compare the exact banked fit with its published D-slot-only follow-up."""
import gzip
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[2]
FIT=ROOT/'build/fit'
OLD=FIT/'tlb-matched-20261117/banked'
NEW=FIT/'banked-third-20261118'
RUNS=('44160843231','44258633306')
STATS=('ALMs','placed_ALMs','occupied_LABs','registers','design_registers',
       'routing_registers','M10Ks','block_memory_bits','MLABs','DSPs')
SLACK=('setup','hold','recovery','removal','min-pulse')


def direct(row,key):
    return float(re.search(r'\(([-\d.]+)\)',row[key])[1])


def tlbs(fit):
    result={}
    for row in fit['cpu_hierarchy']:
        name=row['Full Hierarchy Name']
        leaf=row['Entity Name']
        if leaf not in ('arm920_tlb','arm920_tlb_bank'):
            continue
        side='D' if 'u_data_cache' in name else 'I'
        if leaf=='arm920_tlb_bank':
            side+=' bank'
        result[side]=dict(ALMs=direct(row,'ALMs needed [=A-B+C]'),
                          registers=direct(row,'Dedicated Logic Registers'),
                          M10Ks=int(row['M10Ks']))
    assert len(result)==4
    return result


def cells(path):
    return [[v.strip() for v in line.split(';')[1:-1]]
            for line in path.read_text(errors='replace').splitlines() if line.startswith(';')]


def clocks(path):
    return [r for r in cells(path/'clocks.rpt') if len(r)>12 and r[1] in ('Base','Generated')]


def exceptions(path):
    return sorted(r for r in cells(path/'constraints.rpt') if r and r[0].startswith('set_'))


def setup_paths(reports):
    text=(reports/'output_files/timing/worst-setup-full.rpt').read_text(errors='replace')
    paths=re.split(r'(?=Path #\d+:)',text)[1:]
    assert paths
    refs=[]
    for block in paths:
        if not re.search(r'\bthird_(va|pa|valid|cb|read_allowed|write_allowed|fsr|external_fsr)\b',block):
            continue
        fields={}
        for label in ('From Node','To Node','Slack','Data Delay'):
            match=re.search(r';\s*'+re.escape(label)+r'\s*;\s*([^;\n]+)',block)
            assert match,label
            fields[label]=match[1].strip()
        refs.append(fields)
    return dict(paths_examined=len(paths),explicit_third_record_paths=refs)


def main():
    fits=[json.loads((d/'verified-fit.json').read_text()) for d in (OLD,NEW)]
    reports=[d/f'quartus-logs-{r}' for d,r in zip((OLD,NEW),RUNS)]
    a,b=fits
    for f,r in zip(fits,RUNS):
        assert f['status']=='PASS artifact and source verification'
        assert f['run']['url'].endswith('/'+r)
        assert f['source']['seed']==42 and f['source']['debugger']
        assert f['SDRAM_IO']=='PASS all 16 DQ input/output/OE registers'
    assert a['run']['headSha']=='613a3d62abee103660a2475df4abec89e64b1542'
    assert b['run']['headSha']=='1928aeef68cbd65699014854326c38101f5249a7'
    sa,sb=(f['source']['compiled_source_sha256'] for f in fits)
    assert sa.keys()==sb.keys() and len(sa)==178
    changed={n for n in sa if sa[n]!=sb[n]}
    assert changed=={'rtl/arm920/tlb.sv','rtl/arm/zap_dcache.sv'}
    for key in ('effective_qsf','production_bram_sha256','physical_pll_sha256','unique_module_definitions'):
        assert a['source'][key]==b['source'][key],key
    assert len(a['corners'])==len(b['corners'])==8
    corners=[]
    for x,y in zip(a['corners'],b['corners']):
        assert (x['MHz'],x['condition'])==(y['MHz'],y['condition'])
        pa,pb=(d/c['directory'] for d,c in zip(reports,(x,y)))
        assert clocks(pa)==clocks(pb),pa
        assert exceptions(pa)==exceptions(pb),pa
        corners.append(dict(MHz=x['MHz'],condition=x['condition'],
                            control={k:x[k] for k in SLACK},
                            candidate={k:y[k] for k in SLACK},
                            delta={k:y[k]-x[k] for k in SLACK}))
    rs={k:(a['resources'][k],b['resources'][k]) for k in STATS}
    ca,cb=map(tlbs,fits)
    ctl,cand=(min(c['setup'] for c in f['corners'] if c['MHz']==78) for f in fits)
    timing_margin=f'Worst 78 MHz setup slack changes from **{ctl:+.3f} ns** to **{cand:+.3f} ns**.'
    if cand<0 or min(c['hold'] for c in b['corners'] if c['MHz']==78)<0:
        timing_gate='The routed candidate misses the 78 MHz timing gate and needs timing work before deployment.'
    else:
        timing_gate='The candidate meets the 78 MHz setup and hold analysis.'
    pulse_paths=[setup_paths(d) for d in reports]
    evidence=dict(status='PASS matched attribution',fits=fits,changed_selected_inputs=sorted(changed),
                  matched_input_count=178,corners=corners,whole_resource_delta={k:y-x for k,(x,y) in rs.items()},
                  direct_tlb=[ca,cb],exported_setup_paths=pulse_paths,
                  worst_78_setup=[ctl,cand])
    receipt=ROOT/'docs/evidence/tlb-banked-third-fit-20261118.json.gz'
    receipt.write_bytes(gzip.compress(json.dumps(evidence,sort_keys=True).encode(),mtime=0))
    lines=['# Routed third D-side mapping on the banked TLB','',timing_margin,timing_gate,'',
           'Both runs used Quartus 17.0.2 with seed 42 and the DDR debugger enabled. The two builds '
           'match on all 178 effective input paths. The hashes differ for the D-cache instance and '
           'its translation controller. The physical 78 MHz PLL, production BRAM and source '
           'module definitions match. Both artifacts pass all 16 SDRAM DQ input, output and '
           'output-enable register checks. The eight scenarios match on clock inventories and constraints.',
           '',f'[Banked control]({a["run"]["url"]}) · [Banked third-slot fit]({b["run"]["url"]})',
           '','## Resources','','| Metric | Banked | Third slot | Delta |',
           '| --- | ---: | ---: | ---: |']
    for k,(x,y) in rs.items():
        lines.append(f'| {k} | {x:,} | {y:,} | {y-x:+,} |')
    lines.extend(['','Direct TLB hierarchy values show local controller and main-bank rows. The whole-design '
                  'deltas also include placement and routing effects throughout the fit.',
                  '','| Row | Direct ALMs A → B | Direct registers A → B | M10Ks A → B |',
                  '| --- | ---: | ---: | ---: |'])
    for side in ca:
        lines.append('| '+side+' | '+' | '.join(f'{ca[side][k]:g} → {cb[side][k]:g}'
                                                for k in ('ALMs','registers','M10Ks'))+' |')
    lines.extend(['','## Routed timing','','Slacks are in nanoseconds. The 104 MHz entries use the same routed '
                  'netlist with the alternate clock constraint.',
                  '','| MHz and model | Setup A → B | Δ setup | Hold A → B | Recovery A → B | Removal A → B | Min pulse A → B |',
                  '| --- | ---: | ---: | ---: | ---: | ---: | ---: |'])
    for c in corners:
        label=re.search(r'display_name: (.+)',c['condition'])[1]
        def pair(key):
            return f'{c["control"][key]:+.3f} → {c["candidate"][key]:+.3f}'
        lines.append(f'| {c["MHz"]} {label} | {pair("setup")} | {c["delta"]["setup"]:+.3f} | '+
                     ' | '.join(pair(k) for k in SLACK[1:])+' |')
    worst_paths=[]
    for f in fits:
        corner=min((c for c in f['corners'] if c['MHz']==78),key=lambda c:c['setup'])
        worst_paths.append(corner['global_paths'][0])
    lines.extend(['','## Interpretation','',
                  f"The fit adds **{rs['ALMs'][1]-rs['ALMs'][0]:,} whole-design ALMs**, "
                  f"while the directly attributed D translation controller adds "
                  f"**{cb['D']['ALMs']-ca['D']['ALMs']:.1f} ALMs and "
                  f"{cb['D']['registers']-ca['D']['registers']:.0f} registers**. "
                  f"Both fits use {rs['M10Ks'][1]} M10Ks. The candidate leaves "
                  f"{4191-rs['occupied_LABs'][1]} LABs and {553-rs['M10Ks'][1]} M10Ks available.",
                  '',
                  "The slow-corner worst path shifts from the CPU data-cache fast-hit path into "
                  "UPP block control to the reset-drain path into D-cache MVA storage. "
                  f"The worst 78 MHz path data delays are {worst_paths[0]['Data Delay']} ns "
                  f"and {worst_paths[1]['Data Delay']} ns. "
                  f"The candidate's path has {worst_paths[1]['logic_levels']} levels "
                  f"and {worst_paths[1]['data_Routing Element']} ns of routing delay. "
                  f"The 1,000-path export includes {len(pulse_paths[1]['explicit_third_record_paths'])} "
                  "paths with explicit third-record signal names. This counts names in the "
                  "exported paths and has limited visibility into logic merged by the fitter.",
                  '',
                  "Keep the third slot as a measured performance candidate and address timing "
                  "before release. The RBF is retained with its negative timing evidence."])
    lines.extend(['','## Artifacts','','| Run | RBF SHA-256 |',
                  '| --- | --- |'])
    for r,f in zip(RUNS,fits):
        lines.append(f'| {r} | `{f["artifact"]["sha256"]}` |')
    lines.extend(['','[Machine evidence and routed endpoints](evidence/tlb-banked-third-fit-20261118.json.gz) · '
                  '[Combined-source functional qualification](cpu-thumb-early-load.md)'])
    (ROOT/'docs/tlb-banked-third-fit.md').write_text('\n'.join(lines)+'\n')
    print(timing_margin,{k:y-x for k,(x,y) in rs.items()},ca['D'],cb['D'])
    print('Exported worst setup paths',[(p['paths_examined'],len(p['explicit_third_record_paths'])) for p in pulse_paths])


if __name__=='__main__':
    main()
