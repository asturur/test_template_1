# Read-only USB/JTAG diagnostics investigation — 2026-11-12

## Finding and current limits

A small read-only Virtual JTAG endpoint is a viable design to investigate for
replacing the diagnostic **renderer**. It can observe the FPGA independently
of emulated ARM execution and HPS/Linux. It is not present in the current core.
The monitor, first-fault capture, panic record and trace recorder must remain.
Do not remove the screen until the cable/host and a fitted hardware prototype
have demonstrated equivalent fault information during a real boot.

The DE10-Nano USB-Blaster II connection is **Mini-B, J13**, not Micro-USB.
Its separate UART-to-USB connection is also Mini-B; Micro-USB is the USB OTG
connection. Terasic's [getting-started guide](https://www.terasic.com.tw/attachment/archive/1046/Getting_Started_Guide.pdf)
identifies the USB-Blaster connection and driver setup. Intel's
[board guide](https://www.intel.com/content/www/us/en/developer/articles/guide/terasic-de10-nano-get-started-guide.html)
distinguishes UART Mini-B and OTG Micro-B. Full PDF retrieval timed out in this
audit; connector information was available in the indexed official material.

JTAG does not automatically produce a serial port or expose a soft ARM's
registers. A custom endpoint must explicitly expose our observations. ZAP's
fetch PC is an observed fetch virtual address, **not a retirement PC**; JTAG
cannot retroactively turn it into one or inspect arbitrary CPU registers.

No JTAG hardware was connected or enumerated. `quartus_stp`, `jtagconfig` and
`openocd` are absent from this Mac's command path. Quartus has no native macOS
flow according to [Altera support](https://community.altera.com/discussions/quartus-prime/to-install-quartus-prime-lite-software-in-a-mac-system/329726).
A supported Linux/Windows host with USB-Blaster II access is the baseline for
validation. An Apple Silicon VM/container and USB forwarding are **unverified**;
the existing ARM simulation container is not proof of JTAG access. No Quartus
package, driver or alternative USB stack was downloaded or installed.

## Current source boundaries

- `rtl/ngage_mister.v`: `diagnostic_values` is24x32 bits from
  `ngage_debug_monitor`; `panic_report` is99 bits from `ngage_diagnostics`.
- `ngage_debug_monitor` retains counters and first data-fault context. Preserve
  it. It already stages fault/ACK observations to protect timing.
- `ngage_debug_video` adds a767:0 value snapshot,99-bit panic snapshot, text,
  glyph selection and video pipeline. This is the removal target after proof.
- `ngage_diagnostics` retains a64-entry trace and the existing one-clock,
  16-bit NGD read interface. Keep export compatibility and recorder semantics.
- The earlier completed-fit report attributed836.3 ALMs to renderer **plus
  monitor**, and349.9 to recorder/export.836.3 is not the removable renderer's
  measured saving. New JTAG hub/CDC/selection logic also costs area; compare
  whole fitted designs before claiming net savings.

`Template.sv` currently ties its UART outputs low. Framework
`sys/sys_top.v` connects these core UART signals to a hard HPS peripheral
UART instance. This does **not** establish a direct connection to J13 or the
board's physical USB-serial console. A UART alternative needs a verified HPS
UART/device-tree/forwarder path; do not simply wire diagnostic bytes to
`UART_TXD` and assume a Mac terminal will receive them.

## Recommended minimal endpoint

Use the Cyclone V `sld_virtual_jtag` infrastructure with a narrow register
reader, no soft Nios processor, no Avalon bus fabric and no SignalTap capture
array. Intel documents [Virtual JTAG](https://www.intel.com/programmable/technical-pdfs/683705.pdf)
and the [DR shift API](https://www.intel.com/content/www/us/en/docs/programmable/683432/23-2/tcl_pkg_jtag_ver_1-0_cmd_device_virtual_dr_shift).
The same virtual IR/DR and device-lock commands are listed in the
[Quartus17.1 command catalog](https://resources.altera.com/quartushelp/17.1/tafs/tafs/tafs.htm).
This establishes an API family near our17.0 toolchain, not a tested17.0 IP build.
The archived IP PDF URL did not fully fetch; verify the exact17.0 instance
parameters and ports from the build toolchain before implementation.

A host polls observations into JSONL/text; JTAG itself is host-clocked rather
than a free-running USB stream. Initial target4..10 complete polls/second,
roughly128 bytes of payload per poll (512..1,280 bytes/s). TAP/USB transaction
overhead and actual achievable rate require measurement. Full instruction
streaming at78/104 MHz is outside this design.

Proposed read-only register map (word indices, not guest MMIO addresses):

| Index | Content |
| --- | --- |
|0|Magic and protocol version|
|1|Build identifier / schema revision|
|2|Transport state and reset generation|
|3|Host response sequence|
|4..27|Existing24 monitor values, unchanged order|
|28..30|Three panic words|
|31|Panic seen mask plus reserved zero bits|
|32..33|Start/end emulated-cycle stamps for a host poll|

Optional later recorder reads should expose existing NGD words, with explicit
read ownership against disk export; no trace pop, clear or implicit CPU reset.
Keep the initial endpoint a live-register reader, not a second trace buffer.

### Clock crossing and response protocol

A candidate protocol uses virtual IR to select an observation word and request
its sample; virtual DR returns a framed response containing magic/version,
requested index, response sequence, ready flag and32-bit data. Exact packing
is a prototype decision. Host IR updates while a request is busy must be
rejected or explicitly queued; never silently replace an outstanding request.

Use a request/ack toggle handshake between TCK and `clk_sys`, each with proper
two-flop synchronizers. Hold index stable until acknowledged. In `clk_sys`,
sample the selected32-bit observation into a response holding register before
acknowledging. Keep response data stable until the next accepted request.
Only after synchronized ACK may TCK capture the response into its shift
register. Account for the response-data path as a bundled-data CDC: review
constraints and prove settling; do not synchronize a wide live bus bit by bit.
The CPU has no dependency on request, ACK, connection status or host readiness.

Avoid a naive867-bit system snapshot plus867-bit TCK shift copy: that can
replace the renderer with comparable or larger FF storage and muxing. Start
with32-bit held responses and a narrow framed shift register. Request counters,
reset generation and status must resynchronize after TCK reset/disconnect,
cold FPGA reset and reconnect; warm phone reset retains the existing fault
record as before. A stopped system clock must return busy/timeout explicitly.

A poll is **not an atomic24-word CPU snapshot**. Label it as individually
sampled observations with a time interval. First-fault/panic records are
already sticky, so repeat and check their generation/mask for a consistent
record. If an atomic live snapshot becomes necessary, design and account for
that storage explicitly rather than presenting mixed-time words as coherent.

### Host access

On the validated host, enumerate the cable/device using `jtagconfig` and the
Quartus JTAG package. A script launched with `quartus_stp -t reader.tcl` would:

1. Locate the expected Cyclone V and specific Virtual JTAG instance; read and
   reject unknown magic/schema/build instead of selecting the first TAP.
2. Open the device and acquire a bounded `device_lock`.
3. Use `device_virtual_ir_shift` to request one word, then
   `device_virtual_dr_shift` to poll framed data until matching ready/index/
   sequence or a deadline. Never issue FPGA programming, CPU halt or guest writes.
4. Release the device lock between bounded poll batches, including error paths;
   timestamp and decode responses into JSONL, preserving raw words.
5. Reconnect cleanly after unplug, core reload or other JTAG tool ownership.

Altera's sample documents locking and virtual IR/DR access. No reader script
is represented as working here: no endpoint or supported cable host exists
in this session yet. A later open-source/macOS host can be evaluated after
the simple Quartus path works; a raw USB-Blaster driver alone is not sufficient
without support for the SLD virtual hub protocol.

## Implementation gates and tests

1. **Host/cable proof first.** Enumerate J13 on a supported host without
   programming the FPGA. Confirm instance discovery and exclusive-lock recovery.
   No area or renderer changes for this step.
2. **Standalone bridge prototype.** Unit tests with unrelated TCK/system rates,
   stopped/resumed TCK, stopped system clock, back-to-back requests, busy writes,
   partially shifted frames, warm/cold reset, reconnect and changing live words.
   Assert that each accepted index produces its correct held response and cannot
   affect phone bus ACK/IRQ/clock enable. Verify Verilog-2001 and reset/CDC design.
3. **Fit alongside display.** Compile an explicit endpoint-enabled build with
   the existing screen retained. Add real TCK/generated-clock constraints and
   scoped CDC constraints; do not hide ordinary system paths with broad false
   paths. Measure whole-core ALMs/M10Ks and78 MHz closure; keep104 MHz objective.
4. **Board equivalence.** Poll during boot/logo/screensaver and key input;
   compare fault/panic words with screen and NGD export. Unplug/replug and leave
   the reader absent for hours without affecting execution. Confirm retained
   first-fault data after warm reset. Distinguish wake-to-logo from an actual
   reset using reset generation/cycles, rather than screen appearance alone.
5. **Remove renderer only after equivalence.** Use a compile-time display
   selection so glyph/snapshot logic is actually omitted; a runtime Phone menu
   choice does not save gates. Preserve normal LCD video timing/pipeline and
   aspect ratio, monitor/recorder, panic capture and NGD export. Remove the
   obsolete display OSD option only in that qualified build. Compare fitted
   net area and timing including JTAG hub, not the old gross836.3-ALM group.

No production JTAG logic or diagnostic-removal switch was added in this
investigation. The existing visual diagnostics remain available until the
replacement is demonstrated on hardware.

## DDR3 + Linux/SSH and Symbian process/log visibility

### Recommendation

For routine process/startup inspection, investigate **existing guest text output
and an SSH-readable DDR3 event ring before making JTAG the main transport**.
JTAG remains useful for independent first-fault/panic access when HPS is unavailable.
This is an added investigation/design path, not implemented capture hardware.
No MiSTer SSH session or live disk/simulation was read for this audit.

The required information is different from a PC snapshot:

- A **process inventory** lists existing processes and their threads; it can
  include names/IDs, owner, state, priority and exit reason when available.
- A **startup timeline** records creation, resume and exit events over time.
  A single memory snapshot misses processes that already exited.
- A process may exist while all its threads are blocked. Reporting "running"
  requires thread/scheduler state and the current thread, not just a name or
  an open executable file.
- A successful create request is not proof of resume, progress or a healthy UI.
  Capture result/exit information and correlate with emulated time/reset generation.

### What Linux can access today

Phone working RAM is the external16 MiB SDRAM module, reached through
`ngage_sdram_arbiter`/`ngage_sdram_adapter`. It is **not a region of HPS DDR3**,
so Linux `/dev/mem` cannot directly read it through the DDR address mapping.
The CPU's dirty D-cache and write buffer also contain architectural data that
may not yet appear in external SDRAM. Pausing alone does not make a physical
RAM image cache coherent. Physical dumps alone can therefore omit recent
process pointers, names or formatted messages.

Our existing firmware/flash backing is HPS DDR3 through the framework
`sysmem_lite` FPGA-to-SDRAM port. RTL currently uses:

| Backing | Core byte address |
| --- | --- |
| ROM reservation window |`0x30000000..0x313effff`|
| C: raw flash4 MiB |`0x31400000..0x317fffff`|
| PMM64 KiB |`0x31800000..0x3180ffff`|

These values describe current RTL, **not a newly approved free Linux memory
allocation**. `Template.sv` still explicitly marks the base reservation as
requiring installed Main/Linux-map verification. Before direct HPS access or
adding a ring, inspect the installed memory map, device tree, kernel command
line and Main's reservations. Do not choose a supposedly free adjacent address
or overwrite framebuffer/ALSA/Main allocations. This investigation did not
verify a live board reservation.

The direct FPGA-to-SDRAM path does not provide MPU cache coherence; Altera's
[Cyclone V guidance](https://docs.altera.com/r/docs/683360/18.0/an-796-cyclone-v-and-arria-v-soc-device-design-guidelines/fpga-to-hps-sdram-access?contentId=8kWLOyQcYS5O8tznOcLWdg)
requires an appropriate coherent bridge or managed cache policy when sharing
data. A Linux reader needs a verified mapping/cache policy and barriers, not
an assumption that ordinary `mmap` and FPGA writes are coherent. A reserved
uncached diagnostic mapping or a small driver with correct DMA synchronization
is the baseline to evaluate. Never create cached/uncached aliases casually.

### Route A: compact DDR3 event ring — preferred transport experiment

Reuse the current DDR request/ownership arbitration rather than add another
memory controller or a wide live CPU debug bus. A small bounded queue accepts
**selected events only**: process/thread create/resume/exit, debug text and the
existing faults. A low-priority writer drains those into a separately verified
reserved DDR ring. Do not mirror every fetch, all SDRAM writes or cache lines:
that would cost bandwidth, area and timing on this slow core.

Make the producer nonblocking: when a queue/ring is full or the host is absent,
drop whole records and increment a visible drop counter; never backpressure
CPU/SDRAM/IRQ to preserve diagnostics. Preserve priority first-fault/panic
storage independently, so a full ring cannot erase the original failure.
JTAG and SSH should read the same schema where practical.

Proposed records: magic/schema/build/firmware IDs, boot generation, monotonic
sequence, emulated-cycle timestamp, event kind, payload length, typed payload,
and integrity/commit marker. Initialize validity explicitly. Write payload
and metadata before publishing the committed sequence; verify the framework's
write-completion/ordering contract first. The Linux reader copies records and
rechecks sequence/commit before accepting them. Define wrap, overwrite and
host-lag behavior; malformed/partial records are rejected, not interpreted as
kernel pointers. A read-only host can track its cursor locally; a shared tail
write is unnecessary for the first version.

After mapping proof, a small HPS helper would write JSONL or a raw capture to
an ordinary Linux file and stream it over SSH. The Mac needs SSH rather than
USB-Blaster/Quartus for normal use. Reading DDR over SSH is feasible in
architecture; no current helper, allocation or hardware collector is claimed.
A framework diagnostic virtual-disk extension is an alternative transport if
safe direct mapping is awkward: HPS then reads the ordinary image file rather
than physical memory. Existing S3 NGD is only a bounded trace/fault export;
it does not currently export process lists or arbitrary SDRAM.

### Route B: process data snapshot and offline EKA1 decoder

A read-only SDRAM-export master could copy selected pages or a full16 MiB
snapshot into a verified DDR staging area, then Linux retrieves it through SSH.
Reuse the existing memory arbitration, respect SWP/accepted ownership, bound
CPU contention and stop cleanly on reset. Metadata must include ROM/hash,
physical spans, MMU/CP15 state, reset generation and capture interval. Live
copies are time-skewed and can follow freed/reused objects; label them as such.

A correct frozen architectural snapshot additionally requires either:

1. A new **non-resetting** quiesce/drain operation plus coherent cache readout
   or a merged RAM+dirty-cache/write-buffer export; or
2. A guest-side observer that accesses objects through the CPU/cache and emits
   a bounded software snapshot at an OS-safe point.

Current OSD **CPU Hold asserts reset** (`Template.sv`/`ngage_mister`), including
DMA reset: it is not a debugger halt and must not be used as the proposed
snapshot primitive. No CPU/DMA reset or cache-maintenance injection was added.
A forced cache clean changes execution and can fail during a crash; do not
present it as passive access.

An offline decoder must be tied to this NEM-4 **EKA1** kernel revision. Identify
its process/thread object containers, current-thread pointer, names, ID/state
fields and virtual-to-physical mapping from the exact firmware. EKA2 source
layouts and EKA2L1's host-side C++ process vector are not compatible memory
layouts to copy. Validate pointers against captured spans, alignment, bounded
list lengths and object invariants; reject cycles, freed entries and unknown
versions. Start with names/IDs and alive/blocked/current-thread distinctions;
add richer state only after the corresponding fields are verified.

Alternative software observation could enumerate `TFindProcess`/`TFindThread`
through guest APIs and emit names/status without reverse-engineering every
kernel offset. That requires a matching old Symbian SDK/ABI, successful guest
execution and an explicitly selected helper; it is not an invisible stock-ROM
change, and creating a helper changes the observed process set. It cannot be
the sole route for diagnosing failures before user-side startup.

### Route C: existing guest log files and debug output — actual firmware leads

A read-only static scan of local `firmware/SYM.ROM` (SHA-256
`afc1cc8b693f2b68d23ca203aa4d4eb4266baad4ab718f013a33b915d39574ef`)
found1,017 directory entries, including `FLogger.dll`, `FLogSvr.exe`,
`LogServ.exe`, `EStart.exe` and `Startup.app`. Examples below are **ROM file
offsets**, not live RAM addresses or evidence that a service is running:

| Finding | Offset | Implication |
| --- | --- | --- |
| `FLogger.dll`: UTF-16 `C:\\LOGS\\` |`0x004cf058`|A file-logger service/path exists; inspect which callers enable/use it.|
| Fax module: `C:\\LOGS\\FAX\\FAXLOG.TXT` |`0x004b60e0`|Component-specific log candidate, not a process timeline.|
| `Startup.app`: key scan-code debug format |`0x00bc2724`|Potentially useful for the key-to-logo behavior.|
| `Startup.app`: animation-cancelled format |`0x00bc29d0`|A lead for startup/UI progress.|
| `Startup.app`: animation-state-change format |`0x00bc2a24`|A lead for distinguishing redraw/animation behavior from reset.|

The Startup key handler constructs a descriptor from its debug format and
calls thunk `0x50bc15a0`, whose table entry resolves to `0x503b409c`.
That routine formats a message, sets debug operation14 and calls gateway
`0x503ac790`, containing `svc #0xc00097`. This is a static, unchanged-firmware
**debug-output path**; it is not evidence that the message goes to a C: file,
that its kernel backend retains it, or that it executes in the failing boot.
The local HLE reference also labels low SVC index`0x97`/operation14 as debug
print, but it substitutes its own kernel and does not establish our phone's
output device. Public [Symbian debug declarations](https://github.com/SymbianSource/oss.FCL.sf.os.kernelhwsrv/blob/0c3208650587ac0230aed8a74e9bddb5288023eb/kernel/eka/include/e32debug.h)
confirm the API family; their newer kernel implementation is not an EKA1
layout reference.

Therefore trace this firmware's kernel debug dispatch and its final sink:
serial/MMIO, debug buffer, file or deliberate discard. **Do not assume
`RDebug::Print` writes persistent logs.** If a real byte-output MMIO sink
exists, capture there without adding process-list logic. Otherwise consider
an explicitly opted-in message collector at a verified executed debug-call
boundary. Capturing a speculatively fetched SVC address alone is insufficient;
its descriptor pointer/length and buffer can be cached and process-mapped.
Our current public CPU debug ports do not expose all argument registers or
CP15 state, so this needs a designed observation point rather than claiming
an existing wire can retrieve the text.

Likewise `LogServ.exe`/the phone's "Logs" app should not be mistaken for a
general kernel/process trace. Presence of a logging DLL, a format string, or
`C:\\LOGS\\` does not establish that an enabled retail logger writes it.
Determine prerequisites, directory creation and backend behavior first. No
`epocwind.out` path appeared in this static scan; do not assume an emulator
host logfile exists on the phone.

C: persistence is a raw NOR/LFFS image even though the mounted file is named
`.vhd`; it is not a Linux-mountable FAT partition. For file-log inspection,
finish a controlled guest save, wait for completion, stop new background
passes and copy the image; preserve its hash/firmware identity. `sync` on Linux
alone cannot flush guest dirty data or guarantee a guest file is closed.
Parse a copy with a verified LFFS reader or export via guest filesystem APIs.
ASCII/UTF-16 searches are an initial triage only: flash journal/deleted pages,
fragments and stale contents cannot establish a current file or process state.
The supplied expanded retail C: tree has no `logs` directory; that old snapshot
does not prove the current guest creates no logs. No active SD image was read.

Local scan/offset/thunk evidence:
`scratch/ngage2-integration/jtag-diagnostics-20261112/` and the small maintained
[evidence summary](evidence/symbian-diagnostics-leads-2026-11-12.json).

### Ordered follow-up and tests

1. **Static sink/log audit first.** Complete debug SVC/backend cross-references
   and identify actual enabled file-log callers/creation conditions. Retain
   exact firmware hashes and separate dead strings from executable paths.
   Validate independently with bounded synthetic inputs, without polling or
   modifying the other chat's simulation. A later board observation must show
   a message generated by the unchanged firmware before claiming availability.
2. **Existing file triage when a saved image is available.** Copy/hash stable
   C: and PMM, identify LFFS records and recover verified logs. Test erased,
   partial/interrupted and modified images; distinguish live files from stale
   flash data. No write/mount repair against the user's original image.
3. **HPS reservation/transport proof.** On the actual installed Main/Linux,
   verify reservations and coherency, then use a separate test region/pattern.
   Test producer/reader races, barriers, torn record rejection, wrap, host absent,
   overwrite/drop counts, reboot and reconnect. Do not overwrite ROM/C:/PMM.
4. **Minimal selected-event collector.** Prefer verified text/lifecycle events
   over raw RAM polling. Test exact payloads, accepted versus speculative calls,
   overflow, reset generation and no CPU/IRQ backpressure. Measure ALMs, timing,
   DDR contention and the existing LCD/MMC throughput before replacing anything.
5. **Process-state decoding if logs are insufficient.** Establish version-matched
   EKA1 offsets or a declared guest helper; test known created/resumed/blocked/
   exited processes, rapid exits, invalid lists, cache-only changes, address-space
   switches and concurrent mutation. Distinguish snapshot inventory from history.
6. **Renderer removal gate unchanged.** Demonstrate useful process/debug/fault
   output over SSH or JTAG through real startup/key behavior before omitting
   visual diagnostics. Keep independent sticky first-fault/panic capture even
   if Linux, the guest filesystem, or the text logger stops working.
