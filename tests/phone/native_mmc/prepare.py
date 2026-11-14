from pathlib import Path
import hashlib,json,struct,subprocess
root=Path(__file__).resolve().parents[3];out=root/'build/sim/unit-native-mmc';out.mkdir(parents=True,exist_ok=True)
rom=(root/'build/firmware/nem4-factory/core.bin').read_bytes();sha=hashlib.sha256(rom).hexdigest();assert sha=='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
b=rom[0x3f4000:0x3f6000];(out/'driver.hex').write_text(''.join(f'{v:08x}\n' for v in struct.unpack('<2048I',b)))
symbols={x[2]:int(x[0],16) for l in subprocess.check_output(['arm-none-eabi-nm',str(out/'program.elf')],text=True).splitlines() if len(x:=l.split())==3}
b=(out/'program.bin').read_bytes().ljust(8192,b'\0');assert len(b)==8192
(out/'program.hex').write_text(''.join(f'{v:08x}\n' for v in struct.unpack('<2048I',b)))
(out/'boundary.hex').write_text(f'e51ff004\n{symbols["kernel_return"]:08x}\n')
(out/'inputs.json').write_text(json.dumps(dict(rom_sha256=sha,original_mmc_code_modified=False,range=['503f4000','503f6000'],scope='Original R2 FSM/event/status functions on ZAP with real host/ICU, independent wire peer; authored delayed IRQ and kernel scheduling boundary spies'),indent=2)+'\n')
