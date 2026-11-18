#!/usr/bin/env python3
"""Write the measured comparison only after both immutable fits verify."""
import hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/fit/tlb-matched-20261117'
load=lambda p:json.loads(p.read_text())
fits={v:load(OUT/v/'verified-fit.json') for v in ['5l','banked']}
a,b=[fits[v] for v in ['5l','banked']]
for f in fits.values():assert f['status']=='PASS artifact and source verification'
sa,sb=[f['source']['compiled_source_sha256'] for f in [a,b]]
assert sa.keys()==sb.keys() and len(sa)==178
changed=[n for n in sa if sa[n]!=sb[n]]
expected=load(ROOT/'docs/evidence/tlb-area-20261117.json')['changed_from_5L']
assert set(changed)==set(expected), (changed,expected)
for k in ['seed','debugger','effective_qsf','physical_pll_sha256','production_bram_sha256','unique_module_definitions']:assert a['source'][k]==b['source'][k],k

def number(row,key,direct=False):
    v=row[key]
    return float(re.search(r'\(([-\d.]+)\)',v)[1]) if direct else float(v.split()[0])
def banks(f):
    return {('I' if 'u_code_cache' in r['Full Hierarchy Name'] else 'D'):dict(subtree_ALMs=number(r,'ALMs needed [=A-B+C]'),direct_ALMs=number(r,'ALMs needed [=A-B+C]',True),placed_ALMs=number(r,'[A] ALMs used in final placement'),registers=number(r,'Dedicated Logic Registers'),M10Ks=int(r['M10Ks'])) for r in f['cpu_hierarchy'] if r['Entity Name']=='arm920_tlb_bank'}
metrics=['ALMs','placed_ALMs','occupied_LABs','registers','design_registers','routing_registers','M10Ks','block_memory_bits','MLABs','DSPs']
delta={k:b['resources'][k]-a['resources'][k] for k in metrics}
record=dict(status='PASS matched physical comparison',changed_selected_inputs=changed,matched_selected_inputs=178,resource_delta=delta,variants={})
for v,f in fits.items():
    record['variants'][v]=dict(commit=f['run']['headSha'],run=f['run']['url'],conclusion=f['run']['conclusion'],artifact=f['artifact'],source=f['source'],resources={k:f['resources'][k] for k in metrics},banks=banks(f),physical_TLB_RAM=f['physical_TLB_RAM'],SDRAM_IO=f['SDRAM_IO'],timing_gate=f['timing_gate'],corners=[dict(MHz=c['MHz'],condition=c['condition'].strip(),setup=c['setup'],hold=c['hold'],recovery=c['recovery'],removal=c['removal'],worst_path=c['global_paths'][0],checks=c['checks'],UCP=c['UCP']) for c in f['corners']])
area=-delta['ALMs'];m10k=b['resources']['M10Ks'];worst={v:{freq:min(c['setup'] for c in f['corners'] if c['MHz']==freq) for freq in [78,104]} for v,f in fits.items()}
recommendation=f'Retain the banked candidate for its measured {area:,} ALM saving and {553-m10k} remaining M10Ks, subject to the recorded cold/mutation latency costs and timing limits.' if area>0 and m10k<=553 else 'Keep the 5L control; the banked candidate does not deliver a usable fitted area saving.'
if worst['banked'][78]<0:recommendation+=' It does not close 78 MHz timing, so it is not a timing-qualified hardware release.'
if worst['banked'][104]<0:recommendation+=' The 104 MHz objective remains unmet.'
record['recommendation']=recommendation
receipt=ROOT/'docs/evidence/tlb-matched-fit-20261117.json';receipt.write_text(json.dumps(record,indent=2)+'\n')
lines=['# Matched 5L and banked-TLB physical fits','',recommendation,'','Both builds used Quartus 17.0.2, seed42 and DDR debugger on. The production PLL stays at 78 MHz; the same routed designs were also analyzed at 104 MHz. No hardware deployment was performed.','', '| Variant | Immutable source | Build | Timing gate |','|---|---|---|---|']
for v,f in fits.items():lines.append(f"| {v} | `{f['run']['headSha']}` | [run]({f['run']['url']}) ({f['run']['conclusion']}) | {f['timing_gate']} |")
lines+=['','## Whole design resources','','| Metric | 5L | 5L + banked TLB | Delta |','|---|---:|---:|---:|']
for k in metrics:lines.append(f"| {k} | {a['resources'][k]:,} | {b['resources'][k]:,} | {delta[k]:+,} |")
lines+=['',f"Capacity: 41,910 ALMs, 4,191 LABs and 553 M10Ks. Banked headroom is {41910-b['resources']['ALMs']:,} ALMs, {4191-b['resources']['occupied_LABs']:,} LABs and {553-m10k} M10Ks. Registers include routing optimization; implementation and routing are reported separately above.",'','## Main TLB hierarchy','','Subtree and direct values are alternative views, never added together. Direct values are the parenthesized Quartus hierarchy values.','','| Bank / metric | 5L | Banked | Delta |','|---|---:|---:|---:|']
for side in ['I','D']:
    for k in ['subtree_ALMs','direct_ALMs','placed_ALMs','registers','M10Ks']:
        x,y=banks(a)[side][k],banks(b)[side][k];lines.append(f'| {side} {k} | {x:g} | {y:g} | {y-x:+g} |')
lines+=['','## Physical RAM proof','','The following are fitted RAM Summary rows, rather than source inference.','','| Variant | RAM | Implemented dimensions A / B | M10Ks |','|---|---|---|---:|']
for v,f in fits.items():
    for r in f['physical_TLB_RAM']:
        name=r['Name'];side='I' if 'u_code_cache' in name else 'D';ram='tag_rows' if 'tag_rows' in name else 'entries'
        lines.append(f"| {v} | {side} {ram} | {r['Implementation Port A Depth']} × {r['Implementation Port A Width']} / {r['Implementation Port B Depth']} × {r['Implementation Port B Width']} | {r['M10K blocks']} |")
lines+=['','## Routed timing','','Setup and hold slacks are nanoseconds; negative setup means timing does not close.','','| MHz / corner | 5L setup | Banked setup | Delta | 5L hold | Banked hold |','|---|---:|---:|---:|---:|---:|']
for x,y in zip(a['corners'],b['corners']):
    assert (x['MHz'],x['condition'])==(y['MHz'],y['condition'])
    lines.append(f"| {x['MHz']} / {x['condition'].strip()} | {x['setup']:.3f} | {y['setup']:.3f} | {y['setup']-x['setup']:+.3f} | {x['hold']:.3f} | {y['hold']:.3f} |")
lines+=['','Worst setup endpoints are retained in the machine evidence. Existing unconstrained external SDRAM delay/forwarded-clock coverage limitations remain; this is not full board timing verification.','', '## Attribution and functional limits','','Both actual checkout SHAs match their publication receipts. All 178 selected input paths match, and only the following seven hashes differ:','']+[f'- `{n}`' for n in changed]
lines+=['','The effective QSF, seed/debugger settings, production BRAM, physical PLL and unique module definitions match exactly. All 60 qualified CPU/integration RTL/header hashes were checked before publication. ZAP patches0081 and0082 replay byte for byte. The normal remote name and `asturur/test_template_1` resolve to the same repository. Both artifacts pass all 16 SDRAM DQ input/output/OE register checks.','', 'The original warmed workloads, JPEG, spans and 224-start/224-clock load stream remain unchanged from qualified 5L. Banked late-row lookups and misses take 2–9 sampled edges; cold wrappers and mutations cost more. The short data-ordering diagnostic regresses 381→455 clocks (+19.42% at zero wait). These measured costs remain relevant despite the fitted area result. See [functional evidence](tlb-area.md) and [5L qualification](cpu-late-operand.md).','','## Retained artifacts','','| Variant | Bytes | RBF SHA256 |','|---|---:|---|']
for v,f in fits.items():lines.append(f"| {v} | {f['artifact']['bytes']:,} | `{f['artifact']['sha256']}` |")
lines+=['','Full source manifests, artifact paths, eight timing corners, RAM rows and resource values are in [machine evidence](evidence/tlb-matched-fit-20261117.json). Complete downloaded reports and bitstreams remain under `build/fit/tlb-matched-20261117/{5l,banked}/`. Reusable preparation/publication/collection helpers are in `tools/tlb_matched_fit/`. No 5M or unrelated optimization was included.']
(ROOT/'docs/tlb-matched-fit.md').write_text('\n'.join(lines)+'\n');print(recommendation);print(delta)
