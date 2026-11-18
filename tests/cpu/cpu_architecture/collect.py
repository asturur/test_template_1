"""Verify source, scoped effects, fixed work and timing across the architecture study."""
from pathlib import Path
import gzip
import json
import statistics
import sys

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'tlb_three_mapping'))
from build import OUT, ROOT, sha
from report import CASE_ORDER, EFFECTS, stream_starts
from sega_scan import fixture, verify, LAST
from trace import events, log_text, scan_intervals, span_recurrence


def load(path):
    return json.loads(path.read_text())


def read_runs(names):
    rows={}
    for name in names:
        d=OUT/name
        r=load(d/'result.json')
        assert r['status']=='PASS',name
        for row in r['rows']:
            k=row['case'],row['profile']
            assert k not in rows
            rows[k]=(row,r.get('build',r.get('manifest')),d)
    return rows


def sample(path,label):
    rows=events(path,label)
    row,=[r for r in rows if r['index']==2]
    return row


def architecture_effects(path,tag):
    rows=[]
    for line in log_text(path).splitlines():
        if line.startswith(tag+' '):
            row=dict(w.split('=') for w in line.split()[1:])
            rows.append({k:int(v,16 if k in ('pc','stores') else 10)
                         for k,v in row.items()})
    assert [r['index'] for r in rows]==list(range(7))
    return rows


def log(dir,key):
    case,profile=key
    return dir/(case+'-'+profile.replace(':','-')+'-0.log')


def architecture_ab():
    ref=read_runs(['arch-reference-work-18','arch-reference-scan-work-18'])
    proto=read_runs(['arch-tagged-work-18-v2','arch-tagged-scan-work-18-v2'])
    assert ref.keys()==proto.keys()=={(x,p) for x in CASE_ORDER for p in ('0:0','2:9')}
    rows=[]
    changed={'rtl/arm/'+n+'.sv' for n in ('zap_writeback','zap_predecode_main','zap_btb',
             'zap_alu_main','zap_fetch_main','zap_mode16_decoder_main','zap_core')}
    for key,(a,ma,da) in ref.items():
        b,mb,db=proto[key]
        assert ma['harness']==mb['harness'] and ma['image']==mb['image']
        x,y=ma['source']['files'],mb['source']['files']
        assert x.keys()==y.keys() and {n for n in x if x[n]!=y[n]}==changed
        for k in ('operations','unit','oracle','variants','warmups'):
            assert a[k]==b[k],(key,k)
        for row in (a,b):
            assert row['repeats_equal']==2 and row['wrong_output_rejected']
        for aw,bw in zip(a['windows'],b['windows']):
            assert {e:aw.get(e) for e in EFFECTS}=={e:bw.get(e) for e in EFFECTS},key
        logs=(log(da,key),log(db,key))
        assert architecture_effects(logs[0],'ARCH_EFFECT')==architecture_effects(logs[1],'ARCH_EFFECT'),key
        if key[0]=='arm-stream':
            assert all(w['starts']==w['start_clocks']==224 for row in (a,b) for w in row['windows'][2:])
            if key[1]=='0:0':
                assert len(stream_starts(da))==len(stream_starts(db))==224
        arm=[sample(l,'ARCH_WINDOW') for l in logs]
        for w,r in zip(arm,(a,b)):
            assert sum(w[k] for k in ('hold','shift','dep','empty','other'))==r['windows'][2]['cycles'],key
        retired=a['windows'][2].get('retire_proxy',a['windows'][2].get('instructions'))
        rows.append(dict(case=key[0],profile=key[1],suite=a['suite'],
                         reference=a['median'],prototype=b['median'],operations=a['operations'],
                         target=a['median']/2,retired=retired,occupancy=arm,
                         raw=[a['windows'],b['windows']],inputs=a['variants']))
    return rows,ref,proto


def scan_hashes():
    rom=(ROOT/'build/firmware/nem4-factory/core.bin').read_bytes()
    case,code=fixture(rom)
    fingerprints=[0xcbf29ce484222325]*2
    def retire(pc):
        # Old ZAP instrumentation derives mode from post-instruction flags
        # for the two ARM BX veneers. Compare the corresponding spelling
        # independently as well as the donor's canonical PC sequence.
        alias=pc+4 if pc in (0x10035020,0x10035030) else pc
        for i,p in enumerate((alias,pc)):
            fingerprints[i]=((fingerprints[i]^p)*0x100000001b3)&((1<<64)-1)
    verify(case,code,rom[0x500000:0x600000],retire)
    retire(0x10000000+LAST+4)   # The immutable exterior ARM return shim.
    return fingerprints


def donor_compare(ref):
    stock=load(ROOT/'docs/evidence/ngage2-vs-5c-20261117.json')
    archived=ROOT/stock['artifacts']['donor']
    arm=load(archived/'result.json')
    assert arm['status']==stock['status']=='PASS'
    sources=arm['manifest']['source']
    assert sources['commit']==stock['donor_revision']
    rows={}
    for r in arm['rows']:
        key=r['case'],r['profile']
        a,ma,_=ref[key]
        manifest=arm['manifest']
        original=manifest['programs'][key[0]]
        z=a['variants'][0]
        assert (z['program_sha256'],z['begin'],z['end'])==(original['sha256'],original['body_begin'],original['body_end'])
        assert z['payload_sha256'] in manifest['payload_sha256'].values()
        assert ma['image']==manifest['image_id'] and a['oracle']==r['oracle']
        assert a['windows'][2]['retire_proxy']==r['windows'][2]['retire_proxy']
        rows[key]=dict(cycles=r['body_cycles_median'],raw_retired=r['windows'][2]['retire_proxy'],
                       normalized_retired=r['windows'][2]['retire_proxy'],archived=True,windows=r['windows'])
    archived_jpeg=load(ROOT/stock['jpeg']['donor_artifact']/'result.json')
    jpeg_manifest=archived_jpeg['manifest']
    assert archived_jpeg['status']=='PASS' and archived_jpeg['wrong_output_rejected']
    assert jpeg_manifest['source']['commit']==sources['commit']
    assert jpeg_manifest['source']['files']==stock['donor_selected_inputs']
    assert jpeg_manifest['rom_sha256']==sha(ROOT/'build/firmware/nem4-factory/core.bin')
    assert jpeg_manifest['oracle']['thumb_bl_suffixes']==stock['jpeg']['thumb_bl_suffixes']
    for r in stock['jpeg']['rows']:
        key='diffuse_m10_8x8_jpeg',r['profile']
        a,ma,_=ref[key]
        donor=r['donor']
        assert donor in archived_jpeg['rows']
        assert ma['image']==jpeg_manifest['image_id']
        assert a['oracle']=={k:v for k,v in jpeg_manifest['oracle'].items() if k!='thumb_bl_suffixes'}
        for z,name in zip(a['variants'],('jpeg','jpeg-wrong-output'),strict=True):
            original=jpeg_manifest['programs'][name]
            assert (z['program_sha256'],z['begin'],z['end'])==(original['sha256'],original['body_begin'],original['body_end'])
        suffixes=sum(stock['jpeg']['thumb_bl_suffixes'].values())
        assert donor['windows'][2]['retire_proxy']-suffixes==a['windows'][2]['retire_proxy']
        rows[key]=dict(cycles=donor['body_cycles_median'],raw_retired=donor['windows'][2]['retire_proxy'],
                       normalized_retired=a['windows'][2]['retire_proxy'],archived=True,windows=donor['windows'])
    fresh=read_runs(['arch-donor-game-18-v3','arch-donor-scan-18-v3','arch-donor-jpeg-extras-18'])
    fingerprints=scan_hashes()
    for key,(b,mb,db) in fresh.items():
        a,ma,da=ref[key]
        assert a['variants']==b['variants'] and a['oracle']==b['oracle'] and ma['image']==mb['image']
        assert b['repeats']==2 and b['negative'] and mb['revision']==sources['commit']
        assert mb['source']==stock['donor_selected_inputs']
        images=[architecture_effects(log(p,key),tag) for p,tag in ((da,'ARCH_EFFECT'),(db,'DONOR_EFFECT'))]
        for x,y in zip(*images):
            assert (x['stores'],x['count'])==(y['stores'],y['count']),(key,x,y)
            if a['suite']=='scan':
                assert [x['pc'],y['pc']]==fingerprints,(key,x,y,fingerprints)
            elif a['suite']!='jpeg':
                assert x['pc']==y['pc'],(key,x,y)
        raw=b['windows'][2]['retire_proxy']
        normalized=raw-b.get('thumb_suffix_retirements',0)
        assert a['windows'][2]['retire_proxy']==normalized,(key,raw,normalized,a['windows'][2])
        rows[key]=dict(cycles=b['body_cycles_median'],raw_retired=raw,normalized_retired=normalized,
                       archived=False,windows=b['windows'],effects=images)
    return rows,fresh


def table(rows,donor):
    lines=['| Workload | Waits | Retired | Combined clocks | 2× budget | Stock donor clocks | Tagged fetch clocks | Δ from combined |',
           '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for r in sorted(rows,key=lambda x:(CASE_ORDER.index(x['case']),x['profile'])):
        d=donor.get((r['case'],r['profile']))
        if d:
            time=f'{d["cycles"]:,}'
            if d['raw_retired']!=d['normalized_retired']:
                time+=f' ({d["raw_retired"]:,} raw retires)'
        else:
            time='—'
        p=(r['prototype']/r['reference']-1)*100
        lines.append(f'| {r["case"]} | {r["profile"]} | {r["retired"]:,} | {r["reference"]:,} | '
                     f'{r["target"]:,.1f} | {time} | {r["prototype"]:,} | {p:+.2f}% |')
    return '\n'.join(lines)+'\n'


def main():
    a,ref,proto=architecture_ab()
    donor,dr=donor_compare(ref)
    scan=('sega-scan','0:0')
    span=('asphalt-double','0:0')
    timing=[scan_intervals(log(ref[scan][2],scan),log(d[scan][2],scan),tag)
            for d,tag in ((dr,'DONOR_EDGE'),(proto,'ARCH_EDGE'))]
    span_timing=[span_recurrence(log(d[span][2],span),tag) for d,tag in ((ref,'ARCH'),(dr,'DONOR'))]
    quality={name:load(OUT/name/'result.json') for name in (
        'arch-interwork-control-18','arch-interwork-candidate-18','arch-tagged-precise-18')}
    quality.update({name:load(OUT.parent/'tlb-area'/name/'result.json') for name in (
        'arch-tagged-cpu-18','arch-tagged-core-18')})
    irq=load(OUT.parent/'cpu-product-bypass/arch-tagged-irq-18-v2/result.json')
    assert irq['source_id']==proto[span][1]['source']['source_id']
    assert len(irq['logs'])==2
    for name,expected in irq['logs'].items():
        assert sha(ROOT/name)==expected and 'PASS multiply IRQ' in (ROOT/name).read_text()
    quality['arch-tagged-irq-18-v2']=irq
    assert all(r['status']=='PASS' for r in quality.values())
    assert len(quality['arch-tagged-cpu-18']['rows'])==22 and len(quality['arch-tagged-core-18']['rows'])==10
    record=dict(status='PASS',rows=a,donor=[dict(case=k[0],profile=k[1],**v) for k,v in donor.items()],
                scan_intervals=timing,span_timing=span_timing,qualification=quality,
                manifests={name:{'full_scan':rows[scan][1],'standard':rows[span][1]}
                           for name,rows in (('reference',ref),('prototype',proto),('donor',dr))},
                drivers={p.name:sha(p) for p in HERE.iterdir() if p.is_file()})
    data=json.dumps(record,sort_keys=True).encode()
    (ROOT/'docs/evidence/cpu-state-tagged-fetch-20261118.json.gz').write_bytes(gzip.compress(data,mtime=0))
    traces={}
    for key in (scan,span,('diffuse_m10_8x8_random','0:0')):
        for name,d,prefix in (('combined',ref,'ARCH_'),('tagged',proto,'ARCH_'),('donor',dr,'DONOR_')):
            traces[f'{key[0]} {name}']=[line for line in log_text(log(d[key][2],key)).splitlines()
                      if line.startswith((prefix+'EDGE ',prefix+'DATA ')) and int(line.split()[1][2:])<12000]
    (ROOT/'docs/evidence/cpu-state-tagged-fetch-20261118.traces.json.gz').write_bytes(
        gzip.compress(json.dumps(traces,sort_keys=True).encode(),mtime=0))
    (OUT/'architecture-ab-table-18.md').write_text(table(a,donor))
    print('PASS',len(a),'prototype rows',len(donor),'donor rows')
    print([(x['pixels'],x['clocks']) for x in timing])


if __name__=='__main__':
    main()
