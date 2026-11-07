# Quartus memory inference audit — 2026-11-07

Evidence: the user's `releases/quartus-logs/` for commit `506f9ea`, Quartus
17.0.2, DE10-Nano `5CSEBA6U23I7`. These are synthesis/fitting results, not a
local estimate. Parsed data and source hashes are preserved in
`scratch/quartus-memory-audit/report.json`; the analysis script is alongside it.
No RTL was changed during this audit.

## Actual failure

The failed fitter estimates **101,673 / 41,910 ALMs (243%)**, with 118,784
registers. Its hard combinational-node limit also fails at 106,367 / 83,820.
Synthesis reports 106,344 ALUTs and estimates 94,602 ALMs; these are different
stages/metrics and should not be conflated. Hierarchy rows include children;
adding parent totals double-counts resources. Parenthesized report counts are
local to that entity.

Memory usage is **2,367,592 / 5,662,720 bits (42%)**. The failed fitter's
`Total RAM Blocks: 0` is not evidence that no RAM inferred: the synthesis RAM
summary explicitly lists the RAM primitives. Physical placement/allocation
was not completed.

## Arrays that did infer RAM

The following groups sum exactly to the synthesis total. All report Simple
Dual Port inferred RAMs; MLAB memory bits are reported as zero.

| Group | Instances | Inferred bits |
| --- | ---: | ---: |
| LCD pixels | 1 | 439,296 |
| Instruction cache line data | 32 byte lanes | 131,072 |
| Data cache line data | 32 byte lanes | 131,072 |
| UPP upload RAM | 4 byte lanes | 524,288 |
| UPP NOS memory | 4 byte lanes | 524,288 |
| UPP auxiliary RAM | 4 byte lanes | 131,072 |
| UPP GPIO bank | 4 byte lanes | 32,768 |
| UPP NOS 4K bank | 4 byte lanes | 32,768 |
| Other phone/CPU RAMs | 13 | 36,657 |
| MiSTer framework | 22 | 384,311 |
| **Total** | **120** | **2,367,592** |

Thus the large framebuffer, cache data and board RAM windows already infer
RAM. DDR-backed firmware/working flash and external SDRAM are not supposed
to become on-chip arrays in this hardware build.

## Arrays implemented as registers and mux logic

These rows have **zero block-memory bits** in the entity report. Counts below
are local, excluding child entities.

| Entity | ALUTs | Registers | Relevant structure |
| --- | ---: | ---: | --- |
| Dirty tracker | 26,523 | 8,360 | 8,320 dirty bits, dynamic reads and several conditional writes |
| D-cache tags | 9,163 | 27,750 | Tag/physical/valid/dirty metadata, 64-way parallel lookup |
| I-cache tags | 6,492 | 12,902 | Metadata, with unused fields optimized away |
| Diagnostic export | 3,351 | 8,211 | 512x16 snapshot, asynchronous consumer read |
| Diagnostic trace | 2,017 | 5,364 | 64 address/data/info entries, asynchronous debug reads |
| Save data-sector buffer | 2,368 | 4,162 | 256x16, asynchronous local and HPS reads |
| Save header-sector buffer | 2,077 | 4,145 | Separate 256x16 instance |
| Diagnostic sector buffer | 1,030 | 4,147 | Separate 256x16 instance |
| UEM registers | 2,292 | 4,488 | 256x16 values plus written flags, combinational readback |
| Sparse registers | 2,286 | 4,032 | Address-tag CAM and values |

Some metadata is intentionally associative/stateful; its use of registers is
not automatically a Quartus inference bug. The dirty bitmap, snapshots and
sector buffers are the clearest candidates for memory-oriented rewrites.
Simply adding `ramstyle="M10K"` does not fix incompatible access/reset/port
patterns.

## Repair order

1. **Dirty bitmap first.** Replace the asynchronous dynamic lookup and multiple
   procedural update sites with explicit RAM ports and synchronous scan reads.
   Preserve concurrent marks, marks on completion, abort/retry, initialization,
   boundaries and out-of-range handling. Read/write collisions require explicit
   forwarding or retry; never depend on undefined RAM read-during-write data.
2. **Snapshot/sector buffers.** Pipeline reads and account for the latency in
   consumers. Re-run actual `hps_io` sequential-word, flush/remount and concurrent
   mutation tests; a one-word slip would corrupt saves. Separate buffers can
   still use small RAM blocks rather than thousands of flip-flops.
3. **Cache metadata organization.** The current 64-way associative lookup has
   parallel comparisons and asynchronous metadata selection. A resource-aware
   banking/read pipeline is needed; blindly converting it to a single RAM
   changes lookup behavior. Preserve cache geometry and architectural behavior,
   and verify CPU/MMU/maintenance plus a new cold boot after timing changes.
4. Review UEM and diagnostic/sparse arrays after the dominant costs are measured.

A new Quartus report is required after each reduction; fitting success cannot
be predicted from subtracting ALUT counts alone. The current build is at 243%
ALMs, so fixing only one memory may be insufficient. Do not reduce cache
capacity, discard save tracking or bypass firmware to hide the problem.

## Other reported issues

The scaler `mode` connection has four bits while the VHDL port expects five;
this is a real critical warning to resolve alongside build work. Width warnings
and one framework combinational-loop report also remain. They do not explain
away the measured register/mux resource cost, and successful fitting would
still require timing, RAM placement and board checks.

## Implemented explicit M10K conversion (2026-11-07)

`rtl/ngage_bram.v` instantiates Intel `altsyncram` under `SYNTHESIS`, with
`ram_block_type="M10K"`, Cyclone V, synchronous address/control capture and
unregistered RAM outputs. It supports simple dual port (one writer), true dual
port (two writers), configurable depth/width and native byte enables. The
non-synthesis array is only a simulator model, not a RAM inference request.

Reference: local JTFRAME revision `31daf06caa873bc09a90af722ac24aa65785d996`,
`modules/jtframe/target/pocket/hdl/ram/jtframe_pocket_dualram.v`. The generic
`jtframe_ram`, `jtframe_dual_ram`, `jtframe_ram16` and related wrappers use
inference; the Pocket wrapper supplied the explicit primitive/clock pattern.
No vendor simulation library or JTFRAME reference checkout is added to Git.

Converted storage:

| Storage | Explicit organization and latency handling |
| --- | --- |
| C:/PMM dirty bitmap | Two independent one-bit write ports; synchronous scan with mark forwarding, scrub and retry retained |
| Three HPS sector buffers | 256x16 true dual port; local/host reads synchronous, bridge/header consumers wait for data |
| Diagnostic snapshot | 512x16 simple dual port; capture/read/fill stages |
| Diagnostic trace | 64x84 simple dual port; registered field/metadata reads and same-address forwarding |
| Both cache data banks | Eight 512x32 simple-dual memories per cache, four byte enables per word |
| Both cache virtual tags | 64 parallel 8x24 simple-dual memories per cache; synchronous lookup, unchanged 64-way / 16 KiB geometry |
| Cache physical metadata | 512x27 dual-port memory for scan/victim; unused standalone hit-PA copy optimizes away in the CPU |
| UPP upload/NOS/GPIO/aux RAM | Existing registered interface now uses explicit 32-bit byte-enabled memories |
| UEM values | 256x16 simple dual port; prime at command acceptance, payload forwarding, three small route mirrors |
| Sparse register payloads | 64x32 byte-enabled RAM; CAM address tags remain registers, UPP waits for synchronous reads |
| LCD framebuffer | 18304x24 simple dual port; packs the two RGB444 pixels, retains CPU-write priority and forwards scan/write collisions |

Cache timing: prime tags on request acceptance; use the registered lookup segment
for the line RAM; wait after changing refill/maintenance indices and re-check
after installation. Hit physical-address debug output takes an extra clock after
the tag result; its unused copy is removed in integrated builds. Victim and scan
physical addresses require a clock after changing their indices.

The first tag conversion passed functional tests but regressed cached ARM ADD
throughput to four cycles/instruction. This approach was rejected. A two-line
(64-byte) streaming register buffer plus two-instruction lookahead bridges the
synchronous tag/data stages. The existing timing regression again measures
exactly one cycle per warm ARM ADD, including cache-line boundaries. Serialized
operations/maintenance clear streaming validity; the D-cache does not enable
this shortcut. ZAP patch 0039 records the lookahead change.

Small resettable/parallel control remains in registers: cache valid/dirty flags,
victim/random state, sparse CAM tags, IRQ/timer/boot registers, small protocol
headers/FIFOs and the streaming pipeline. These have control or associative
access requirements; replacing them with one synchronous RAM would change their
interfaces. This conversion does not claim every flip-flop should be RAM.

Mixed-port read/write data is deliberately `DONT_CARE`. Callers forward it
(bitmap/trace/LCD/UEM), separate the operations, or wait before consuming data.
Do not infer a portable value from the simulator's old-data result. Same-address
dual writes are excluded by the callers.

Validation commands and limits:

- `tests/phone/bram/run.sh` inside `jotego/simulator:arm64`: behavioral tests;
  set `ALTERA_MF` to Intel's `altera_mf.v` for the actual primitive branch.
  Locally mount the library from `~/develop/jtpublicfork` read-only. Widths
  1/16/24/27/32/84, both port modes, byte preservation, non-power-of-two depth,
  last address, power-up zero and read latency are covered.
- Actual primitive-model cache tag/access and dirty bitmap regressions also run;
  they test architectural comparisons/control against Intel's RAM model.
- Existing CPU suite, actual HPS save/diagnostic transfer, full 4 MiB C:/64 KiB
  PMM restore, framebuffer/native-video, board and bounded cold boot checks
  remain the integration gates. See the latest `status.md` for their results.
- Source preflight requires **168 files / nine QIPs**. Quartus supplies
  `altsyncram` as a builtin; no new generated IP/QIP is required for the wrapper.
- Synthesis-path Verilator lint uses the external vendor model (override
  `ALTERA_MF`); it is a syntax/port check, not placement or timing verification.

The new RAM layout changes saved simulation state. Preserve all original
billion-cycle CPU/host pairs and use `--use-saved-build` for that lineage.
New-model boot tests start cold; no old checkpoint is silently upgraded.

**Pending hardware evidence:** run the GitHub Quartus 17 build and inspect the
new RAM summary, M10K allocation, ALMs, fit and 104 MHz timing. Logical bits and
ALUT subtraction cannot predict physical packing; the many shallow parallel
tag banks especially need a measured block count. No fit/resource saving is
claimed until those reports exist.

### Quartus 17 branch-selection correction

Run 42357152231 failed before fitting: Quartus did not define `SYNTHESIS` and
compiled the simulator array, reporting multiple constant drivers. The wrapper
now selects its primitive for either `ALTERA_RESERVED_QIS` (Quartus native,
as used by the Pocket reference) or `SYNTHESIS` (explicit vendor-model tests).
The regression separately preprocesses the Quartus-native branch and rejects
any behavioral-memory declaration. Vendor simulation success alone did not
validate the original Quartus macro environment; do not repeat that assumption.

### Whole-word enable configuration

Run 42357641897 reached the primitive and rejected width_byteena=1 with
explicit byte_size=8 on the 16-bit sector buffer. Single-enable memories now
use byte_size=0 (vendor default/automatic sizing, as in the wizard wrapper).
Byte-enabled 32-bit cache/UPP RAM still uses byte_size=8 and four enables.
The simulation model accepted the former invalid synthesis combination;
primitive simulation is not a substitute for Quartus parameter checks.
