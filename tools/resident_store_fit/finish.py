#!/usr/bin/env python3
"""Create the durable comparison from collected reports; no network or RTL writes."""
from pathlib import Path
import json,re,hashlib,subprocess,collections
ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'build/fit/resident-store-20261116';raw=out/'candidate'
load=lambda p:json.loads(p.read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
b=load(out/'control-summary.json');c=load(out/'candidate-summary.json');run=load(out/'run.json');manifest=load(out/'reconstructed-input-manifest.json')
assert run['headSha']==manifest['actual_commit']=='7aa1a418bbf2d0ba28c215015f10e1412e6dc171'
assert c['scenario_errors']==''
assert 'clock-coverage-PASS.txt' in c['scenarios']['104']['coverage_files']
rdir=raw/'output_files/timing/resident-store'
def cells(p):return [[v.strip() for v in l.split(';')[1:-1]] for l in p.read_text(errors='replace').splitlines() if l.startswith(';')]
def clocks(freq):
 return {r[0]:r[1:] for r in cells(rdir/freq/'corner-1/clocks.rpt') if len(r)>12 and r[1] in ['Base','Generated']}
cl78=clocks('78');cl104=clocks('104');assert cl78.keys()==cl104.keys()
for n in cl78:
 if not n.startswith('emu|pll|'):assert cl78[n]==cl104[n],n
 else:assert cl78[n][13:]==cl104[n][13:],n
core=next(n for n in cl104 if n.startswith('emu|pll|') and 'PLL_OUTPUT_COUNTER' in n)
assert abs(float(cl104[core][1])-1000/104)<0.002
rows78=cells(rdir/'78/corner-1/constraints.rpt');rows104=cells(rdir/'104/corner-1/constraints.rpt')
exceptions=lambda rows:[r for r in rows if r and r[0].startswith('set_') and r[0]!='set_clock_uncertainty']
assert exceptions(rows78)==exceptions(rows104)
corner_results=[]
for freq,scenario in c['scenarios'].items():
 for corner in scenario['corners']:
  d=raw/corner['directory'];row={'MHz':int(freq),'condition':corner['condition'],'path_groups':corner['first_paths']}
  for kind in ['setup','hold','recovery','removal']:
   row[kind]=float(re.search(r'Worst case slack is ([\d.\-]+)',corner[kind])[1])
  row['min_pulse']=float(re.search(r'Worst case slack is ([\d.\-]+)',(d/'min-pulse.rpt').read_text(errors='replace'))[1])
  checkrows=cells(d/'check-timing.rpt');row['checks']={r[0]:int(r[1]) for r in checkrows if len(r)==2 and r[1].isdigit()}
  row['UCP']={r[0]:int(r[1]) for r in cells(d/'unconstrained.rpt') if len(r)==3 and r[1].isdigit()}
  corner_results.append(row)
metrics=['ALMs','registers','M10Ks','MLABs','occupied_LABs','DSPs','placed_ALMs','design_registers','routing_registers']
resource_table={k:{'control':b['resources'][k],'candidate':c['resources'][k],'delta':c['resources'][k]-b['resources'][k]} for k in metrics}
e={'decision':'Retime the shared request/completion-to-probe boundary before CPU admission; do not widen admission yet. Dirty forwarding is not the first timing target.',
 'run':{k:run[k] for k in ['headSha','headBranch','status','conclusion','url']},'base':manifest['base'],'seed':42,'debugger':1,'resources':resource_table,'normal_78':{'control':b['normal_timing'],'candidate':c['normal_timing']},'corners':corner_results,'control_worst_path':b['global_worst_path'],'candidate_worst_path':c['global_worst_path'],
 'coverage':{'core_clock_104':cl104[core],'unrelated_clocks_unchanged':True,'explicit_exceptions_delays_unchanged':True,'explicit_exception_rows':len(exceptions(rows78)),'analysis_error_log':'empty','whole_core_104_signoff':'NOT qualified: missing SDRAM I/O delays/forwarded clock plus hard-IP no-clock/multiple-clock warnings; setup and recovery also fail'},
 'manifest_recovery':{'provenance':manifest['provenance'],'source_count':len(manifest['compiled_source_sha256']),'remote_blob_verified':len(manifest['remote_git_blob_sha1_verified']),'sha256':sha(out/'reconstructed-input-manifest.json')},
 'raw_outputs':str(raw.relative_to(ROOT)),'control_outputs':'/Users/andreabogazzi/Downloads/quartus-logs (1)/','report_sha256':c['report_sha256']}
(ROOT/'docs/evidence/cache-resident-store-pipeline-fit-20261116.json').write_text(json.dumps(e,indent=2)+'\n')
(ROOT/'docs/evidence/cache-resident-store-fit-inputs-20261116.json').write_text(json.dumps(manifest,indent=2)+'\n')
p=ROOT/'docs/cache-resident-store-pipeline-fit.md'
s=p.read_text().replace('The CI manifest captures the source graph and SHA256 of every selected source,\nunique cache/BRAM definitions, effective QSF, exact commit and expected payloads.\nLocal source-graph preflight found 178 required files. The post-fit CI manifest\nis the authoritative record of the actual job inputs.', 'The source graph records 178 selected files. The in-job manifest helper failed\non container/host path translation; the recovered input manifest below combines\nthe actual CI graph, verified immutable tree blobs and effective seed/debug\nsettings. It is explicitly labeled reconstructed, rather than a successful\nin-job manifest step.')
s+='''## Result and recommendation

**Retime before CPU admission.** The candidate fits below both planning stops,
but fails routed setup at 78MHz and the correctly derived internal 104MHz
scenario. The shared reset/completion/TLB/fast-ACK→probe-owner path remains the
first boundary to break. The new owner→probe and certificate→owner paths also
miss 104MHz; dirty forwarding has margin and is not the first retiming target.
No RTL retiming, CPU admission change, second seed or deployment was performed.

## Measured resources

'''
s+='| Resource | Control | Candidate | Delta |\n| --- | ---: | ---: | ---: |\n'
for k,r in resource_table.items():s+=f"| {k} | {r['control']:,} | {r['candidate']:,} | {r['delta']:+,} |\n"
s+='''
The candidate leaves **915 ALMs** to the 40,450 planning stop and **18 M10Ks**
to the 521 stop. Twelve LABs are empty versus zero in the control. This is a
first-placement screen, not proof of room for the rest of the CPU pipeline.
The −59 ALM whole-design delta is not a claim that added pipeline logic is
free: D-cache access hierarchy grows from 3,957.4 to **4,123.9 ALMs** (+166.5),
while physical optimization/packing changes elsewhere. Whole-design implementation
registers increase 555 and routing registers decrease 485, producing net +70.
Data-cache line/tag memories stay at 82 M10Ks; instruction cache stays at 77.

## Routed timing, same 78MHz constraints

Normal compile reports below are **Slow 1100mV 100C**, matching the supplied
control's model. Extra corners later in the table are candidate-only analyses.

| Clock | Control setup ns | Candidate setup ns | Delta ns |
| --- | ---: | ---: | ---: |
'''
for tag,title in [('emu|pll|','CPU/core'),('pll_hdmi|','HDMI'),('sysmem|','HPS user'),("FPGA_CLK1_50","FPGA_CLK1_50"),("FPGA_CLK2_50","FPGA_CLK2_50"),('pll_audio|','Audio')]:
 def setup(j):return next(r['slack_ns'] for r in j['normal_timing'] if r['type'].startswith('Setup') and tag in r['type'])
 bv=setup(b);cv=setup(c);s+=f'| {title} | {bv:+.3f} | {cv:+.3f} | {cv-bv:+.3f} |\n'
s+='''
CPU TNS is −13.963ns versus −13.752ns. CPU hold is +0.194ns versus +0.251ns.
The core violation was already present; its same-corner WNS worsens by 0.515ns.
HDMI setup changes from passing to −0.101ns. Because only cache design files
changed, the HDMI change is a whole-design placement/routing interaction,
not a new HDMI RTL path. It still blocks a passing whole-core result.

## Candidate corner analysis, same routed netlist

Global worst slacks across constrained clocks, ns. At 78MHz fast corners the
worst setup clock is HDMI; at 104MHz fast corners it is the core. Slow corners
are core-limited. These are measured reports, not Fmax conversion or subtraction.

| Scenario | Model / temperature | Setup | Hold | Recovery | Removal | Min pulse |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
'''
for r in corner_results:
 model='slow' if 'model: slow' in r['condition'] else 'fast';temp=re.search(r'temperature: (.*)',r['condition'])[1]
 s+=f"| {r['MHz']}MHz | {model}, {temp}C | "+' | '.join(f"{r[k]:+.3f}" for k in ['setup','hold','recovery','removal','min_pulse'])+' |\n'
s+='''
Worst candidate setup is **−1.520ns at 78MHz** and **−4.725ns at 104MHz**, both
slow −40C. Only the 100C control is available for a same-corner comparison.
At 104MHz slow 100C, recovery also fails **−0.803ns** from
`loader|slot_valid[0]` to `core|reset_drain~SynDup_63`; it is not a store data
path. The 104MHz model retains uncertainty and half-cycle relationships, so
its hold/recovery/minimum-pulse results are separate checks, not inferred from
setup. All reported hold/removal/minimum-pulse minima are positive.

The script's clock-coverage check passes. Actual core waveform is 0/6.410ns
at 78MHz and 0/4.807ns at 104MHz, period 12.820/9.615ns. All nine unrelated
clock rows remain identical. The 51 explicit exception rows (one clock group,
48 false paths, two multicycle paths) are identical; there are 44 uncertainty
rows in each scenario. Generated-clock and uncertainty checks report zero
issues. The one 104MHz PLL cross-check warning is expected from hypothetical
clock retargeting with physical PLL HDL unchanged.

**Full constraint coverage is not qualified.** Candidate UCP still has 20
unconstrained input ports/46 paths and 86 output ports/168 paths in both
scenarios, including external SDRAM. check_timing also reports 2,473 no-clock
objects (HPS/h2f-related hard-IP objects are among them) and 86 multiple-clock
objects in both scenarios. These checks were exported, not waived. Missing
SDRAM min/max I/O delay budgets and the forwarded SDRAM_CLK clock prevent
104MHz I/O signoff. All 16 DQ input/output/OE registers do pass physical I/O
packing, both in CI and an independent local check; that is a distinct result.

## Longest relevant paths and the first retiming boundary

The table uses slow 100C for a direct control match; data / cell / routing are ns.
Full endpoint names and per-corner path hashes are in the evidence JSON and raw
reports. Small IC correction accounts for rounding in the delay totals.

| Path family / endpoints | Data | Cell | Routing | Levels | 78 slack | 104 slack |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
'''
basepath=b['global_worst_path'];s+=f"| Control reset_drain → probe_owner_way[5] | {basepath['Data Delay']} | {basepath['data_Cell']} | {basepath['data_Routing Element']} | {basepath['logic_levels']} | −0.811 | not supplied |\n"
paths=c['scenarios']['78']['corners'][0]['first_paths'];paths104=c['scenarios']['104']['corners'][0]['first_paths']
for key,label in [('reset_to_probe.rpt','Candidate reset_drain → probe_owner_way[5]'),('pipeline_to_probe.rpt','pipe_owner → probe_owner_way[5]'),('any_to_pipeline.rpt','reset_drain → pipe_mva[3]'),('certificate_to_owner.rpt','line_result_tag[2][25] → pipe_owner duplicate'),('dirty_forwarding.rpt','tags commit_selected[10] → commit_dirty[0]')]:
 r=paths[key];v=paths104[key];s+=f"| {label} | {r['Data Delay']} | {r['data_Cell']} | {r['data_Routing Element']} | {r['logic_levels']} | {r['Slack'].split()[0]} | {v['Slack'].split()[0]} |\n"
s+='''
The same-corner worst route still traverses `reset_drain` →
`u_data_completion|o_next` → D-TLB primary-match/fault → adapter `fast_hit` →
probe match/way encode → `probe_owner_way[5]`. Candidate logic depth grows
10→13 and cell delay 4.531→5.239ns; routing decreases 8.703→8.193ns. The
critical-path family predates the candidate, but the candidate does not remove
it and adds pipe_busy/fast-return qualifications to the connected control cone.
One placement cannot attribute the entire −0.515ns regression to one added gate.

At cold slow corner, `postalu2|o_und_ff` → the same probe-owner endpoint is worst:
13.618ns data, 7.272 cell, 6.347 routing, 12 levels; −1.520/−4.725ns at 78/104.
The new `pipe_owner`→probe path is also a real 104MHz violation (−2.497ns cold),
so merely fixing the baseline launch reset net is insufficient.

**First justified boundary:** register the locally owned probe/admission
context after request/translation/class qualification and before probe matching
and way selection. Separate private pre-read scheduling from the same-cycle
fast-ACK/completion-next feedback. Keep immediate reset/kill suppression on
small valid bits; do not send it back through wide payload/way capture enables.
Then revisit certificate→owner qualification, which is itself −1.168ns at
104MHz (100C), with a registered ingress/class/way token rather than another
combinational condition on the present owner capture. Requalify fast-read
ownership and the one-clock store recurrence after either latency change.

The fitted store path **survives optimization**: reports contain actual
`pipe_owner`, `pipe_mva`, certificate→owner and pending/recent dirty-state
paths, not empty/pruned groups. Dirty forwarding remains +2.568ns at 104MHz
100C (+2.631ns cold). Retiming its merge first is not supported by this fit.
The path families and data/dirty memories remain present; a fitter report is
not a new post-fit functional-throughput proof.

## Manifest recovery, raw outputs and stopping point

The job is red for two separate reasons: the normal timing gate, and an isolated
reporting-helper path bug. The helper read `/project/Template.qsf` from the
container graph but tried to relativize it to the host Actions workspace. It
failed before writing its JSON, after the three payload assertions passed.
The full fit, standard timing export and 78/104MHz scenario export all succeeded;
scenario errors.txt is empty. No refit was used to repair this reporting issue.

The durable helper now handles container `/project` paths. The reconstructed
manifest uses the **actual uploaded source graph**, the immutable remote tree,
and exact tagged seed/debug helpers. **177 of 178 selected input blobs** match
the remote tree byte-for-byte by Git blob SHA1 and are recorded by SHA256;
the remaining effective QSF is reconstructed from the exact tagged file plus
42/debug-on selection, confirmed by CI logs and fitter settings. Unique module
definitions and the production BRAM SHA256 are verified. Provenance is labeled
reconstructed, not falsely presented as a successful CI manifest step.

- Raw candidate: `build/fit/resident-store-20261116/candidate/`.
- Finished job log, run metadata, submission/tag/tree identity and parsed summaries:
  `build/fit/resident-store-20261116/`.
- Durable input proof: `docs/evidence/cache-resident-store-fit-inputs-20261116.json`.
- Compact resource/corner/path evidence:
  `docs/evidence/cache-resident-store-pipeline-fit-20261116.json`.
- Post-fit scenario reports: `candidate/output_files/timing/resident-store/{78,104}/corner-{1..4}/`.

The tag and run remain for reproduction. No bitstream was downloaded for
installation, and nothing was deployed. Shared production RTL, checkout/index,
78MHz PLL and the running phone remain untouched. Stop here: repair the shared
probe/admission timing boundary before CPU admission; keep a second seed and
the independent DDR3 experiment separate.
'''
p.write_text(s)
print('Wrote report and durable evidence')
