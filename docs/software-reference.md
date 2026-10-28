# Software reference for firmware bring-up

Current checkpoint and resume tasks: [status.md](status.md).

A software ARM emulator helps by executing the same firmware and exposing its
register, memory, and device accesses. The FPGA CPU can then be checked against
an independent instruction engine while both use the same explicit board model.
This is now implemented in `sim/oracle.py`; the FPGA continues to use ZAP RTL.

## What EKA2L1 supplies

Inspected source revision: `4dfaf5060e3bbb4b7e7bbc26f8ec7ffc2b959bc3`, retained in
`scratch/references/EKA2L1/`. It executes ARM code from the ROM, but creates the
kernel and startup environment on the host rather than reproducing Nokia's
power-on peripheral initialization:

- [`system_impl::load_rom`](https://github.com/EKA2L1/EKA2L1/blob/4dfaf5060e3bbb4b7e7bbc26f8ec7ffc2b959bc3/src/emu/system/src/epoc.cpp#L824-L864)
  parses the logical ROM, creates its filesystem, and maps it at its header address.
- [`initialize_user_parties`](https://github.com/EKA2L1/EKA2L1/blob/4dfaf5060e3bbb4b7e7bbc26f8ec7ffc2b959bc3/src/emu/system/src/epoc.cpp#L1389-L1410)
  installs patches, registers host dispatch functions, and initializes services.
- [`setup_nanokern_controller` / `start_bootload`](https://github.com/EKA2L1/EKA2L1/blob/4dfaf5060e3bbb4b7e7bbc26f8ec7ffc2b959bc3/src/emu/kernel/src/kernel.cpp#L418-L467)
  creates a kernel process and supervisor thread itself.
- [`set_epoc_version`](https://github.com/EKA2L1/EKA2L1/blob/4dfaf5060e3bbb4b7e7bbc26f8ec7ffc2b959bc3/src/emu/kernel/src/kernel.cpp#L507-L548)
  replaces supervisor calls with host library dispatch.
- [`reset_thread_ctx`](https://github.com/EKA2L1/EKA2L1/blob/4dfaf5060e3bbb4b7e7bbc26f8ec7ffc2b959bc3/src/emu/kernel/src/thread.cpp#L150-L184)
  supplies the EKA1 thread entry routine, registers, stack, and CPU state.

These are useful references for later OS interfaces, image loading, display
buffers, and expected game behavior. They do not establish cold-reset values
for the physical flash, PLL, GPIO, or LCD transport registers encountered here.
The supplied rengage project also uses Unicorn but provides a synthetic virtual
map; see [references.md](references.md).

## Our executable comparison

The native software runner uses pinned Unicorn 2.1.4 with its TI925T ARMv4T model.
This is an independent instruction reference, not an exact ARM920T model or
an FPGA CPU replacement. It starts at physical zero in ARM supervisor mode,
with the same local firmware and experimental physical map as the HDL runner.
A pending CP15 control write is checked before the following instruction;
the reference stops if the MMU becomes enabled. The default remains this physical-only boundary. The separate
[MMU-aware option](mmu-reference.md) now runs native translation and validates
post-MMU code/data access conventions; focused ZAP MMU diagnostics remain required.

`sim/oracle_bridge.cpp` exposes the existing C++ `BootProfile` through a small C
interface. Device behavior is shared rather than independently guessed twice.
Every code fetch and data access must be accepted by that bounded model; broad
native engine mappings do not make unknown registers or missing flash bytes valid.
Flash ID/command overlays are temporary and do not modify the ROM payload.

Comparison checks ordered device accesses: read/write, physical address, selected
byte lanes, selected data bytes, and device identity. It also checks the first
unknown operation. Ordinary RAM/ROM traffic and speculative instruction fetches
are excluded because the two CPUs have different pipelines and CP15 reserved bits.
The firmware hash, board-model hashes, profile options and reconstructed-tail
hash must match before a comparison is accepted. An I/O difference or frontier
difference returns failure. If software intentionally stops at MMU enable,
comparison is limited to the HDL prefix ending at its matching CP15 control write;
post-MMU device accesses are excluded and the result names that limited scope.

**What this proves:** two independent CPU implementations make the same observed
device requests on this firmware path under the chosen assumptions.
**What it does not prove:** those assumptions match the actual phone, every CPU
instruction agrees, the CPU is fully ARM920T compatible, or hardware timing works.

## Running

Requirements: native Python, a native C++17 compiler, and the local firmware.
The optional dependency is installed only into `build/oracle/venv`; package cache
and temporary files remain under project `scratch/`.

```sh
make oracle-setup
make sim-oracle
make sim-oracle-ideal-clocks
make sim-oracle-check
make sim-oracle-lcd
# Generate an HDL counterpart with the existing ARM64 simulator image:
make sim-firmware-lcd
# Compare the complete LCD path (repeat --compare for another HDL run):
build/oracle/venv/bin/python sim/oracle.py --ideal-clocks --lcd-probe \
  --no-instruction-trace --max-instructions 50000000 \
  --compare build/sim/runs/firmware-amd16-latency0-ideal-clocks-lcd-probe/bus.tsv
```

`FIRMWARE` selects the local ROM and `BOOT_PROFILE` selects the identity experiment.
Only the inspected N-Gage 4.03 firmware is accepted by the command-line runner.
No proprietary image is downloaded. No Quartus tool is used.

Reports, bus traces, compiler/source provenance, and optional instruction traces
are in `build/oracle/<profile>[-ideal-clocks][-lcd-probe]/`. Normal runs stop at
the first unknown access. Reaching an execution limit is reported as a limit,
not a successful boot. `--no-instruction-trace` omits only the large text log;
all code and data accesses are still validated and the original delay loops run.

## Measured progress

The strict clock-status frontier matches across software and both HDL memory
latencies: 5,506 software instructions, 59 modeled I/O events, first unknown read
`0x0c120020`. The ideal-clock frontier also matches: 6,320 instructions,
123 I/O events, first unknown halfword read `0x0c14f008`.

With the separately enabled LCD probe, the unmodified firmware executes
22,458,929 software instructions, including its busy-wait delays, before stopping
at a missing physical flash payload read at `0x046c001c` (instruction `0x1ea4`).
It emits 75 LCD headers, 18,353 data words, and 18,334 status reads. These include
18,304 screen-clear writes under header `0x8924d67f`, followed by command `0xaf`.
The clear loop covers 176 columns by 208 rows, two pixels per write; the header
requests 54,912 bytes. Transport packing and exact panel identity remain unknown.
No rendered screen or running Symbian session is claimed.

All 36,905 modeled I/O events and the stopping read match HDL at both immediate
and deterministic 0-3 cycle memory latency. HDL stops after 111,002,311 and
154,357,177 harness cycles respectively. The CPU acceptance suite, synthesis-path
lint, and synthetic software-comparison checks pass. The latter reject changed
I/O, a changed frontier, missing events, stale model hashes, other firmware or
profile settings, and a mismatching CLI comparison; they also check the MMU
boundary and a conditionally skipped MMU write.

The missing read corresponds to file offset `0x011c001c` under the current bank
mapping, 28 bytes beyond the supplied ROM image. The scanner at ROM `0x1e24`
checks candidate image signatures at candidate base + `0x1c`. A logical Symbian
ROM dump does not establish the surrounding physical flash contents. The later
[firmware inventory](firmware-inventory.md) recovers additional retail payload
from ROOT. A separate [reconstruction](extension-reconstruction.md) now supplies
explicitly synthetic metadata with unchanged recovered payload. The default
without that option still stops at the missing bytes.


## Physical reads versus logical-ROM backing

A software-emulator return value can identify dump placement when it comes from
an independently modeled physical access. EKA2L1's
[`map_rom`](https://github.com/EKA2L1/EKA2L1/blob/4dfaf5060e3bbb4b7e7bbc26f8ec7ffc2b959bc3/src/emu/kernel/src/kernel.cpp#L1377-L1442)
backs a virtual ROM chunk with the file itself; it does not reproduce the current
physical post-ROM scan. The shared Unicorn/HDL board model is not an independent
source for unknown flash contents either.

The saved trace now shows the current scanner begins exactly after the core ROM
has been mapped, comparing prospective extra-image headers with core version/time
and expected next virtual base. See [flash-layout.md](flash-layout.md) for the
recovered arguments and distinction between expected comparison words and actual
returned data. `make inspect-flash-scan` reproduces that evidence without running
the long LCD delay loops again.


The subsequent [firmware inventory](firmware-inventory.md) finds all 507 additional
NEM-4 files intact in ROOT, linked beyond the core ROM. That is independent input
content, unlike the shared software/HDL device assumptions. The opt-in extension
now preserves those bytes and reconstructs their missing metadata; the physical
map and original metadata remain unverified. A QD developer ROM and its named
drivers/analysis databases are also available as separate references.

## Reconstructed path and the MMU boundary

`make sim-oracle-extension` runs the original firmware with the validated tail and
separate boot-I/O hypotheses. It executes 23,103,894 instructions, stopping at
physical PC `0x2e6c` immediately after the CP15 write requests MMU/caches on with
`c1=0x127f`. The result is `scope_limit`, not a boot-success marker.

The HDL reaches that same control write with TTBR `0x0a074000` and DACR
`0x55555557`. All 36,944 device accesses before the boundary match under both
memory timings. The saved comparator can reuse the software bus/result:

```sh
python3 sim/compare_saved_oracle.py \
  --oracle build/oracle/amd16-ideal-clocks-lcd-probe-extension-boot-io/result.json \
  --hdl build/sim/runs/firmware-amd16-latency0-ideal-clocks-lcd-probe-extension-boot-io/bus.tsv \
  --hdl build/sim/runs/firmware-amd16-latency3-ideal-clocks-lcd-probe-extension-boot-io/bus.tsv
```

This avoids repeating 23 million instructions just to compare existing traces.
The twelve comparator checks include stale model/reconstruction rejection,
selected-byte handling, conditionally skipped MMU writes, and exclusion of later
HDL I/O. The HDL continues into virtual startup and reaches the UEM ADC; that
later execution is outside this physical-only software reference's validation.

The later `--mmu-reference` mode continues independently through virtual startup,
ADC and timer setup. Its first complete 36,977-event comparison is archived under
`build/checkpoints/adc-first-timer-write/`. That software exposed the subsequent
BTB tag-collision failure; see [branch-prediction.md](branch-prediction.md).
`--compact-bus` reduces log volume while preserving all memory checks and modeled
I/O. There are now sixteen oracle/comparison checks. Current full-path results
and any limits are in [status.md](status.md).
