# Invalid bitmap MMIO observer — retain for reproduction only

Do not apply prepared/observer.py: the hardware boot entered the kernel stop
loop before setup. No Calendar finding is qualified by this run. The USER
paths attempted direct debug MMIO; permissions/context are not board-qualified.
Removal and original hashes/settings are recorded in restored-after-invalid.json.

The exact Thumb trampoline itself passes isolated actual ZAP in Verilator at
waits0/3 (10435/15826cycles,172bytes). This does not cover MMU/cache mappings,
USER permissions, the full function or the phone. First bench failures were
bench bugs: speculative fetch-PC completion and dangling-else write decoding.
The corrected tb.v exits only on an executed memory marker after continuation.

Rebuild trace.S from make.py (depends on tracked LCD-port generator), assemble
for armv4t, link trace.ld, objcopy binary and nm symbols.txt. Run test.py with
cached Linux Unicorn as in the LCD-port README. Then run zap/build-fixture.py
from repo root to generate private native/payload/program hex, and compile
zap/tb.v with ngage_bram.v,ngage_cpu.sv,rtl/arm/*.sv,rtl/arm920/*.sv in existing
jotego/simulator:arm64. Run obj/Vtb +wait=0 and +wait=3. Never track firmware
pages/generated hex or giant logs. No production RTL modification.
