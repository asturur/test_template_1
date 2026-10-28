# Reconstructed extension and MMU bring-up

Checkpoint: [status.md](status.md). Work performed 2026-10-27.
The five-patch timing/prefix evidence below is historical. The resumed ADC,
MMU-aware reference and six-patch verification are documented in the checkpoint,
[mmu-reference.md](mmu-reference.md) and [branch-prediction.md](branch-prediction.md).
This is a simulator experiment, not an authentic recovered flash image.

## What was built

`sim/rom_extension.py` emits a separate tail at
`build/firmware/nem4-extension/extension.bin` with a sidecar `extension.json`.
The original `firmware/SYM.ROM` and supplied ROOT/filesystem inputs are unchanged.

- Original core SHA-256 remains
  `afc1cc8b693f2b68d23ca203aa4d4eb4266baad4ab718f013a33b915d39574ef`.
- Recovered ROOT SHA-256 remains
  `2fb73cd7e2269fcb2a11733061a84a78ed3e61803be7021a9672d594bd5378b4`.
- The 2,293,760-byte tail covers virtual `0x511c0000..0x513f0000` under the
  existing, still provisional physical-bank mapping.
- Its SHA-256 is
  `cf3ca0899718d8d28a03339b044266ae0c4b98876daf6de93dee4c8a99002dd5`.
- The ROOT block is preserved byte-for-byte at inferred virtual
  `0x5123e338..0x51370000`. The builder verifies all **1,524 files** in the
  resulting combined filesystem against the supplied files.
- Missing EKA1 directory records are rebuilt from known names, sizes, attributes
  (assumed read-only for additional files) and payload addresses. There are 97
  directories. The two top child directories retain the addresses already named
  by recovered ROOT: System `0x5123da34`, Nokia `0x5123e304`.
- A synthetic root list at `0x511c0080` selects the preserved ROOT directory.
- A synthetic 128-byte extension header starts at the first post-core candidate,
  `0x511c0000`; its declared image ends at `0x51370000`.
- Uncovered bytes inside this bounded type-1 ROM-bank tail are explicitly assumed
  erased (`ff`), including the remaining space after the reconstructed image.
  User-storage/type-3 windows are not given backing by this operation.

The manifest lists recovered and synthesized spans, hashes, and assumptions.
Both runners require that manifest, validate the original core and tail hash,
and independently check that the recovered ROOT bytes have not changed.
A changed reconstruction cannot silently be compared with an older HDL input.
Default runs without `--rom-extension` retain the original missing-flash stop.

## Header and directory evidence

The N-Gage bootstrap itself checks candidate `+0x0c` (next virtual base),
`+0x10` (size), and `+0x1c/+0x20/+0x24` (matching core version/time). Its caller
reads candidate `+0x14` for the combined root-list pointer. These exercised
fields drive the reconstruction. Own version/time mirror the core, checksum
is synthesized as zero, and unused fields are not authenticated against a phone.

Published Symbian references were retained through `gh` in
`scratch/references/symbian-kernel/` at commit
`0c3208650587ac0230aed8a74e9bddb5288023eb` of
[SymbianSource/oss.FCL.sf.os.kernelhwsrv](https://github.com/SymbianSource/oss.FCL.sf.os.kernelhwsrv/tree/0c3208650587ac0230aed8a74e9bddb5288023eb).
Its later `e32rom.h` documents extension headers and combined roots, but differs
from this EKA1 firmware's field order and directory encoding. The reconstructed
records follow the supplied EKA1 data: UTF-16 names, four-byte entry alignment,
and no later EKA2 `TRomDirSortInfo` trailer. Do not copy the later layout blindly.

## Separate boot I/O experiment

`--boot-io-probe` requires the reconstructed extension and existing ideal-clock/
LCD experiment. It introduces these additional explicit hypotheses:

| Item | Behavior |
| --- | --- |
| `0x0c150212` | Selected halfword assumed zero for its GPIO read/modify/write |
| `0x0c150000` | Selected low halfword assumed zero as a cold-reset status |
| `0x0c0047fd..0x0c0047ff` | Exactly three cold-start flag bytes assumed zero |
| `0x0c150034` | Observed halfword control writes retained as a latch |
| `0x0c150420/22/26` | Bounded control-bus transport with immediate completion bit `0x400`; written device registers can be read back, unwritten device values remain unknown |
| `0x0c004720..0x0c004745` | Software register-shadow table; initially unknown, initialized by the ROM's 19 halfword writes |

The control-bus address whitelist follows the 19-entry table at ROM `0x6d80`,
plus the explicit reset-status register `0x35`. Configurations 7/8/15/16 follow
the inspected routines; the later conversion adds configuration `0x8f` and exact
command `0x239`. Read bit `0x100` and write bit `0x200` are direction flags, not
part of a device-register key. Written values are hypothetical latches rather
than a full UEM model. The known directional ADC/watchdog register is handled
separately: no written value can substitute for its ADC reading. PMIC/UEM side
effects, interrupt behavior, reset contents and timing remain unverified.
No arbitrary zero response is given to an unwritten device read.

The shadow table is writable storage whose values come from firmware, not a new
reset-value assumption. Its initial values come from ROM `0x9fd8`. The two-byte
gap before the previously modeled executable scratch at `0x0c004748` stays unknown.

## Measured progress and comparison limits

The extension-only experiment passes the former missing-flash read and reaches
GPIO read `0x0c150212` (aligned bus address `0x0c150210`, upper halfword).
The software executes 23,103,769 instructions; immediate-memory HDL stops after
115,507,566 cycles. All 36,922 modeled device accesses and that stopping read match.
That report predates the subsequent expansion of the boot-I/O probe.

With the boot-I/O experiment, software executes **23,103,894 instructions** and
stops intentionally at PC `0x2e6c`, immediately after CP15 c1 is written with
`0x127f`. The HDL requests:

- Translation table base: `0x0a074000`.
- Domain access control: `0x55555557`.
- Control: `0x127f` (MMU and caches enabled).

The software reference remains physical-only; it does not validate later MMU or
kernel execution. The saved comparator now cuts the HDL trace at its first MMU
enable event and labels the result **pre-MMU prefix**. Immediate and
delayed runs both match all **36,944** device accesses to this boundary. The
observed transition cycles are 115,508,331 and 160,257,860 respectively.

The HDL has executed virtual startup addresses `0x5000xxxx` after this boundary.
An early pass reached the software-shadow-table write at physical `0x0c004720`.
After modeling those initialized bytes, a delayed run entered the firmware's
explicit lookup-failure loop at virtual `0x50003524` instead of reaching the next
control-bus transaction. That loop has now been isolated to the asynchronous
cache-miss load-width bug, fixed by CPU patch 0005; see [cpu-patches.md](cpu-patches.md).
The focused diagnostic passes both memory timings. Full firmware now gets past
the failed lookup. Original upstream ARM32/Thumb regressions pass with all five
patches; synthesis-path lint also passes. This is not a Symbian boot or kernel-entry claim.

The page tables recovered from the saved software writes map both virtual
`0x00006d80` and `0x50006d80` to physical `0x00006d80`, containing the register
lookup array. This rules out simply assuming the low literal address is absent.
`build/sim/pre-mmu-ram-words.json` retains that reconstructed RAM state.
The FPGA trace showed correct bus words but an incorrectly un-narrowed cache-miss
register completion; patch 0005 fixes that distinct CPU issue.

## Current post-MMU frontier

The corrected CPU reaches physical `0x0c150426` (aligned bus address
`0x0c150424`, upper-halfword select `0xc`) after requesting command `0x239`,
configuration `0x8f`, payload `0x6800`, then command `0x13a`. The retained TriX
UEM implementation identifies this sequence as a channel-6/BSI ADC conversion;
see [uem-control-bus.md](uem-control-bus.md) for the exact firmware/reference
evidence and next implementation slice.

Immediate-memory HDL stops after **115,513,670 cycles**; delayed memory after
**160,264,088 cycles**. The result explicitly names the missing ADC channel,
without fabricating an analog sample. The CPU has crossed into virtual startup,
but no software-reference comparison covers execution after MMU enable.

TLB diagnostics also report ignored section-format bits (bit 4 and bits 15:12).
They need an ARM920T-specific audit; do not silence them or change semantics based
only on a warning emitted by ZAP's different architecture generation.

## Reproduction and saved outputs

```sh
make prepare-rom-extension
make check-rom-extension
make sim-oracle-check
make sim-compat
make sim-oracle-extension
make sim-firmware-extension FIRMWARE=firmware/SYM.ROM
# Delayed-memory FPGA counterpart:
python3 sim/run.py --firmware firmware/SYM.ROM --boot-profile amd16 \
  --ideal-clocks --lcd-probe --rom-extension --boot-io-probe --compact-trace \
  --latency 3 --max-cycles 220000000
# Compare already saved traces; no delay loops or CPU builds are repeated:
python3 sim/compare_saved_oracle.py \
  --oracle build/oracle/amd16-ideal-clocks-lcd-probe-extension-boot-io/result.json \
  --hdl build/sim/runs/firmware-amd16-latency0-ideal-clocks-lcd-probe-extension-boot-io/bus.tsv \
  --hdl build/sim/runs/firmware-amd16-latency3-ideal-clocks-lcd-probe-extension-boot-io/bus.tsv
```

The reconstruction's six tests verify determinism, unchanged core, all files,
payload integrity, recovered ROOT integrity even after a changed overall digest,
and wrong-core rejection. The software comparator's twelve tests include
reconstruction mismatch and the MMU comparison boundary. Latest CPU acceptance
and board bounds pass. The new masked-self-loop harness checks distinguish a
permanent IRQ/FIQ-masked loop from an IRQ-enabled idle loop.

Compact runs retain a bounded post-MMU retirement tail in `instructions.tsv` and
physical data-transaction tail in `memory-tail.tsv`. The harness stops repeated
unconditional self-branches with IRQ/FIQ masked after 32 retirements, reporting
`firmware_loop`, so a firmware failure does not consume the entire cycle budget.
