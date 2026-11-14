# Native LCD observation through existing debug59 sink

Experimental observation only. See docs/phone-functions.md and docs/status.md.
The earlier calendar-lcd-20261114 RDebug-service probe is INVALID: kernel ABT
before Calendar. Do not use its prepared observer. This implementation has no
SWI, service call, heap, mode/IRQ change or SPSR write. It emits bounded ASCII
and eight hexadecimal digits by STRB to original VA59000000→PA0DE00000.

Entry wrappers restore every register/CPSR before the exact original first
instruction and function body. Header12 only at native caller5040184C samples
the pending DMA's existing16-bit buffer at row60 when in-band, otherwise the
first row, pixel25. Zero count/other callers skip. Native source formula:
object[r5+38]+352*row+2*25. Line entry samples its own32-bit source pixel25.

Build from repository root:

```
python3 scratch/calendar-lcd-port-20261114/make.py
arm-none-eabi-gcc -c -march=armv4t -marm scratch/calendar-lcd-port-20261114/trace.S -o scratch/calendar-lcd-port-20261114/trace.o
arm-none-eabi-ld -T scratch/calendar-lcd-port-20261114/trace.ld scratch/calendar-lcd-port-20261114/trace.o -o scratch/calendar-lcd-port-20261114/trace.elf
arm-none-eabi-objcopy -O binary scratch/calendar-lcd-port-20261114/trace.elf scratch/calendar-lcd-port-20261114/trace.bin
arm-none-eabi-nm scratch/calendar-lcd-port-20261114/trace.elf > scratch/calendar-lcd-port-20261114/symbols.txt
docker run --rm --pull=never --network none -v "$PWD:/work" -w /work -e PYTHONPATH=/work/scratch/profile-records-20261113/linux-unicorn/site --entrypoint python3 jotego/simulator:arm64 scratch/calendar-lcd-port-20261114/test.py
python3 scratch/calendar-lcd-port-20261114/prepare.py
```

280original/traced differential cases cover USR/SVC/IRQ/UND CPSR/SPSR, ARM/Thumb
return and in-band DMA samples; native conversion executes, port helpers spied.
Private ROM/toolchain/Linux wheel cache are existing local inputs, not downloads.
Read mister-control software-observer procedure before hardware use. Generated
observer defaults read-only and enforces full image, fresh physical Hold/saved
Run off, saveOff/zero bus history/advancing telemetry before --apply. Never patch
warm firmware. Reload removes it; verify complete original ROM/settings/disks.

Interpret only complete messages; interrupts/native output may interleave, and
reader gaps preclude absence/timing claims. No pending band/frame completion or
physical-panel behavior is established solely by a window/header entry.
