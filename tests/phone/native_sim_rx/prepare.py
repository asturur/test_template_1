from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[3];out=root/'build/sim/unit-native-sim-rx';out.mkdir(exist_ok=True,parents=True)
p=root/'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll';b=p.read_bytes();sha=hashlib.sha256(b).hexdigest();assert sha=='e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1';body=b[96:];a=0x51635000-0x5149d280
for name,data in [('native',body[a:a+4096]),('program',(out/'program.bin').read_bytes().ljust(4096,b'\0'))]:
 assert len(data)==4096
 (out/(name+'.hex')).write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,4096,4)))
(out/'inputs.json').write_text(json.dumps(dict(nos_sha256=sha,native_instructions_modified=False,scope='Original SIM FIFO RX routine on ZAP, authored FIFO or production SIMIF/card; scheduler no-op leaf, no complete RTOS/boot claim'),indent=2)+'\n')
