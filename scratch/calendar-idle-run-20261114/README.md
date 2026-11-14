# Calendar/Agenda CIdle scheduling observation

Observe native CIdle Start50399D70, post-SetActive50399DA4 and RunL50399DAC.
Only USER mode and callback addresses in native Calendar or AgnModel/Agnsynca/
Agndasvr ranges log. Entry checks restore all GPRs/CPSR/SP/LR before exact
original displaced push/pop and body. READY logs iStatus+4 and priority+14
AFTER native RequestComplete and SetActive; native first Start stores callback
at+18 and param+1C. This observes readiness/execution, never substitutes callback,
completion, deadline, data, priority, or service response.

Run make.py, assemble trace.S with arm-none-eabi-as -march=armv4t,link trace.ld,
objcopy trace.bin,nm symbols.txt.504Unicorn baseline/traced entry cases pass;
USER/SVC/IRQ/UND, boundary callbacks, ARM/Thumb callers, all state/live stack/
object preserved. Native print service ABI is spied; remainder function is
not simulated. A saved-R4 bug in the READY observer was caught and corrected
in these tests BEFORE hardware use. READY reads original R4 from savedSP+24,
not the R4 reused for CPSR/guard scratch.

prepare.py reuses standalone exit tracer/checksum update. Apply ONLY via
mister-control's fresh physical Hold/full original image/zero history guards.
All apply/image/checksum checks must pass; restore original saved Run/saveOff
then start CPU. Reload removes all observation; full original-media verification
afterward. No FPGA/PLL/resource/production RTL change. Hardware status/results
in docs/status.md and docs/phone-functions.md.
