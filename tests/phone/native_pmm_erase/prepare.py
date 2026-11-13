"""Copy unchanged native NOS Intel erase/status code into the CPU fixture."""
from pathlib import Path
import hashlib,json,struct,sys
sys.path.insert(0,str(Path(__file__).resolve().parents[3]/'tools'))
import service_firmware
from build_virtual_sim import rules,decode16
root=Path(__file__).resolve().parents[3]
out=root/'build/sim/unit-native-pmm-erase';out.mkdir(parents=True,exist_ok=True)
source=root/'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll'
raw=source.read_bytes()
assert hashlib.sha256(raw).hexdigest()=='e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1', 'unsupported NOS image'
b=raw[96:]
# Native 5167EF28 erase and 5167F020 status/array restoration, no stubs.
base,end=0x5167e000,0x51680000
data=b[base-0x5149d280:end-0x5149d280]
assert len(data)==8192
# NOS code is relocated by51400000 from these encrypted physical addresses.
# Verify the whole fixture against the original service containers as well as
# the retained native DLL dump; no accidental patched reference can pass.
raw=bytearray(b'\xff'*service_firmware.BACKING_SIZE)
for kind,spec in service_firmware.PROFILES.items():
    source_path=root/'firmware/NEM-04 v.04.03 N-GAGE'/spec[0]
    service_firmware.apply(raw,service_firmware.parse(source_path.read_bytes(),kind),kind)
assert hashlib.sha256(raw).hexdigest()=='88fd596a23269ecb0d9f7544d540c59010d276574dbe3d0262c870c429e58329'
physical=base-0x51400000
rule=rules()
original=b''.join(struct.pack('<H',decode16(struct.unpack_from('<H',raw,a)[0],a,rule)) for a in range(physical,physical+len(data),2))
assert original==data,'native driver differs from original loaded firmware'

(out/'native.hex').write_text(''.join('%08x\n'%int.from_bytes(data[i:i+4],'little') for i in range(0,len(data),4)))
(out/'native.json').write_text(json.dumps({'source':str(source.relative_to(root)),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'base':hex(base),'bytes':len(data),'native_erase':hex(0x5167ef28),'native_poll':hex(0x5167f020),'native_amd_erase':hex(0x5167f1c4),'native_amd_program':hex(0x5167f094),'fixture':'chip0 base0, delay calibration104; no driver helper stubs','modified_guest_instructions':False,'original_service_backing_sha256':hashlib.sha256(raw).hexdigest(),'physical_rom_offset':hex(physical),'verified_original_bytes':len(data)},indent=2)+'\n')
data=(out/'program.bin').read_bytes();assert len(data)<=4096;data=data.ljust(4096,b'\0')
(out/'program.hex').write_text(''.join('%08x\n'%int.from_bytes(data[i:i+4],'little') for i in range(0,len(data),4)))
