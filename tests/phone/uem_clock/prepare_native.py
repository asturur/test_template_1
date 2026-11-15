"""Reuse the native CPU/HAL bus fixture with unmodified ecust RTC code."""
from pathlib import Path
import hashlib,json,sys
root=Path(__file__).resolve().parents[3]
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
rom=(root/'build/firmware/nem4-factory/core.bin').read_bytes()
sha=hashlib.sha256(rom).hexdigest()
assert sha=='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
for name,data,size in [('original',rom[0x300000:0x400000],0x100000),('program',(out/'program.bin').read_bytes(),8192)]:
 assert len(data)<=size
 data=data.ljust(size,b'\0')
 (out/f'{name}.hex').write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,len(data),4)))
s=(root/'tests/phone/native_cbus/tb.v').read_text()
s=s.replace('reg clk = 0, reset = 1;', 'reg clk = 0, reset = 1;\n    reg [32:0] timestamp = 0;\n    integer clock_valid = 1;')
s=s.replace('.power_pressed(1\'b0)', '.power_pressed(1\'b0), .host_timestamp(timestamp)')
s=s.replace('if (!cbus_data[26]) $fatal', "if (address == 32'h58150420 && !cbus_data[26]) $fatal")
s=s.replace("value != 32'h50415353 || status_reads != 2 || writes != 3 || route3b != 16'h1234", "value != 32'h50415353 || status_reads < 5 || writes < 5")
s=s.replace('native CBUS result=%h reads=%0d writes=%0d route=%h','native RTC result=%h reads=%0d writes=%0d route=%h')
s=s.replace('PASS original NEM-4 CPU/CBUS transfer, unchanged HAL, reset-idle/completion and payload wait=%0d cycles=%0d', 'PASS original NEM-4 RTC read/coherence/validity through CPU and native HAL wait=%0d cycles=%0d')
s=s.replace('build/sim/unit-native-cbus/',out.as_posix()+'/')
s=s.replace('repeat (5) @(negedge clk);', '''if (!$value$plusargs("clock_valid=%d", clock_valid)) clock_valid = 1;
        ram[32'h4000 >> 2] = clock_valid;
        timestamp[31:0] = 32'd45296;
        if (clock_valid != 0) timestamp[32] = 1;
        repeat (125) @(negedge clk);''')
(out/'tb.v').write_text(s)
(out/'inputs.json').write_text(json.dumps(dict(original_sha256=sha,original_code_modified=False,scope='original ecust counter/coherence reader and init validity decision, native CBUS/HAL on current CPU; not full boot/calendar persistence'),indent=2)+'\n')
