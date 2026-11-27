from pathlib import Path
from hashlib import sha256
import json, re

area = Path('scratch/v5-peripheral-divide')
dst = Path('docs/evidence/local/v5-104-peripheral-admission-20261124')
phases = [(1,0),(2,0),(2,1),(3,0),(3,1),(3,2)]

def load(path):
    return path.read_text().splitlines()

def digest(value):
    return sha256(value).hexdigest()

def counts(lines):
    result, = [line for line in lines if line.startswith('PACE ')]
    return {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',result)}

def matched(lines, signatures):
    assert all(any(line.startswith(token) for line in lines) for token in signatures), signatures

def stats(d,base,field):
    delta=d[field]-base
    return d | dict(delta_cycles=delta, delta_us=delta/104, delta_percent=100*delta/base,
                    duration_us=d[field]/104)

stock=[]
for wait in (0,3):
    ref=None
    for div,phase in phases:
        lines=load(area/f'stock/stock-{wait}-{div}-{phase}.log')
        matched(lines,['PASS original NEM-4 keypad'])
        mmio=[l for l in lines if l.startswith('MMIO ')]
        assert len(mmio)==44
        if div==1: ref=mmio
        assert mmio==ref
        info=counts(lines)
        if div==1: base=info['cycles']
        assert info['cycles']-base==info['blocked']
        stock.append(dict(div=div,phase=phase,memory_waits=wait,**stats(info,base,'cycles'),
                          ordered_mmio_sha256=digest(('\n'.join(mmio)+'\n').encode())))

directed = []
for keypad in (0,1):
    ref=None
    for div,phase in phases:
        lines=load(area/f'directed/run-{keypad}-{div}-{phase}.log')
        outcomes=[line.split(' ',3)[3] for line in lines if line.startswith('DONE ')]
        samples=[line.split(' ',2)[2] for line in lines if line.startswith('SAMPLE ')]
        assert len(outcomes)==307 and len(samples)==308
        if div==1: ref=(outcomes,samples)
        assert ref==(outcomes,samples)
        directed.append(dict(div=div,phase=phase,keypad=keypad,replies=len(outcomes),
                             sample_records=len(samples),**counts(lines),
                             trace_sha256=digest(('\n'.join(outcomes+samples)+'\n').encode())))
        
gpio=[]
for div,phase in phases:
    lines=load(area/f'mixed/gpio_stress-{div}-{7 if div==1 else 1}-{phase}.log')
    matched(lines,['PASS 512 GPIO'])
    info=counts(lines)
    if div==1: base=info['guest']
    assert info['guest']-base==info['blocked']
    assert info['GPIO']==2050 and info['MMC']==0 and info['MMIO']==2050
    gpio.append(dict(div=div,phase=phase,**stats(info,base,'guest')))

mixed=[]
modes={'baseline':[(1,7,0)]}
modes.update({kind:[(d,mask,r) for d,r in phases if d>1]
              for kind,mask in [('gpio',1),('mmc',2),('all_mmio',4)]})
for scope,cases in modes.items():
    for div,mask,phase in cases:
        lines=load(area/f'mixed/upp_stress-{div}-{mask}-{phase}.log')
        matched(lines,['PASS production UPP DDR RAM','PASS native LCD grants',
                       'PASS PCM/LCD/MMC coexistence','PASS authored ARM CMD24'])
        info=counts(lines)
        samples=[(m[1],m[2],m[3]) for line in lines if (m:=re.fullmatch(r'PCM_SAMPLE \d+ (\d+) (\w+) (\w+)',line))]
        assert len(samples)==128 and int(samples[-1][0])-int(samples[0][0])==275167
        if div==1:
            reference=samples
            base=info['guest']
        differences=[i for i,(a,b) in enumerate(zip(reference,samples,strict=True)) if a[1:]!=b[1:]]
        assert differences==([2] if scope in ('mmc','all_mmio') else [])
        if scope=='gpio': assert info['guest']==base and info['GPIO']==0 and info['blocked']==0
        pcm_hash,=[m[1] for line in lines if (m:=re.search(r'^PASS production UPP DDR RAM.*PCM hash=(\w+)',line))]
        checks=[l for l in lines if l.startswith('PASS ')]
        mixed.append(dict(div=div,scope=scope,phase=phase,**stats(info,base,'guest'),
                          pcm_differing_sample_indices=differences,pcm_hash=pcm_hash,
                          first_pcm_sample_cycle=int(samples[0][0]),pcm_sample_span=275167,
                          pcm_differences=[dict(index=i,baseline=reference[i][1:],actual=samples[i][1:]) for i in differences],
                          checks=checks))
d=dict(status='MEASURED',production_commit='e7f1e31ea4f6d51e9e59463a7f13168b9a8f4530',
       retained_source='e9552bd8e2a395dca1770abf8d23e4b1d66c1ca5',system_clock_mhz=104,
       control_tree='8406276acdc60d658e189d09d31b0699217717ba',
       model='Phase-gate initial CPU-to-UPP request admission. All existing active handshake and device clocks remain.',
       stock_factory_core_sha256='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524',
       stock_factory_app_range='0x50320000 to 0x5041ffff',
       stock_factory_app_sha256=(area/'stock/app.sha256').read_text().strip(),
       cpu_payload_mmio={'fixed_windows':105,'native_frames':4,'recorded_mmio':0},
       stock=stock,directed=directed,gpio_stress=gpio,mixed=mixed,
       admission_rtl_sha256=digest((area/'mixed/source/rtl/ngage_upp.v').read_bytes()),
       verified_sources={name:digest((area/name).read_bytes()) for name in
          ('mixed/source/tests/phone/mmc_mister/tb.v','mixed/gpio.S','directed/tb.sv','stock/tb.v')})
(dst/'receipt.json').write_text(json.dumps(d,indent=2)+'\n')
for name,suite,base,field in (
    ('stock no other waits',[r for r in stock if r['memory_waits']==0],7302,'cycles'),
    ('stock three waits',[r for r in stock if r['memory_waits']==3],12660,'cycles'),
    ('GPIO/EUART stress',gpio,91443,'guest'),
    ('mixed MMC',[r for r in mixed if r['scope']=='mmc'],1168777,'guest'),
    ('mixed all MMIO',[r for r in mixed if r['scope']=='all_mmio'],1168777,'guest')):
    for div in (2,3):
        x=[r for r in suite if r['div']==div]
        e=[r[field]-base for r in x]
        print(name,div,min(e),max(e),f'{min(e)*100/base:.6f}',f'{max(e)*100/base:.6f}',
              f'{(min(e)+base)/104:.6f}',f'{(max(e)+base)/104:.6f}')
