# USER scanline observation

Observation only at original Thumb entry 50559228; no firmware/deadline/data
substitution. Native six-instruction prologue is replayed, preserving original
GPRs/CPSR/SP/LR at continuation (native frame 52bytes). USER metadata uses
native RDebug::Print503B409C, never kernel-service hooks/direct MMIO. Filter:
point.y multiple32. No extra FPGA debug logic.

Assemble trace.S with local arm-none-eabi-as -march=armv4t, link trace.ld,
objcopy trace.bin and nm to symbols.txt. Run test.py with existing Docker and
cached Linux Unicorn.36cases pass, native debug service ABI spied. That alone
does not qualify real service/runtime cost or remaining function behavior.

prepare.py reuses the guarded standalone native exit observer/checksum update.
Use only skill mister-control fresh physical Hold procedure and full original
image/zero-history/apply verification. Restore exact saved Run/saveOff before
starting. Never apply warm. Remove by original reload and full image/settings/
C/PMM verification. See docs/phone-functions.md and docs/status.md for actual
hardware results and gaps; do not infer complete call coverage across gaps.
