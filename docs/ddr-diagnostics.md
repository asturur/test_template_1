## 2026-11-13: DDR is the only runtime diagnostic transport

Diagnostic-disk S3, Export OSD, HPS export controller/buffers and disk CLI/tests
are removed. HPS has only C:/PMM/MMC slots0/1/2. DDR snapshot/text addresses,
wire version and reader are retained; the retired disk-busy status bit is0.
The DDR recorder read port is direct, with no export arbitration/allow_capture
input. Source/history below describes the original qualification build where
applicable. See [diagnostic-disk-retirement.md](diagnostic-disk-retirement.md).

# DDR3 runtime diagnostics (2026-11-12)

Priority: understand Symbian startup using runtime DDR3 readback. C:\logs work
is deferred. Disk saving follows diagnostics; changed sectors alone do not
establish a completed save. The other chat's frozen simulations/checkpoints
are not inputs to this change and were not accessed.

## Implemented, not yet qualified on hardware

`Template.sv` enables two producers on the existing firmware-loader service
port. Loader requests have priority. Diagnostic responses retain the accepted
owner even if a download arrives meanwhile. No extra arbitration stage is
inserted in the CPU/flash path. Diagnostics still consume shared DDR bandwidth;
this is not a promise of zero contention. PLL and constraints remain78 MHz;
104 MHz remains the design objective.

* Text captures committed one-byte writes to the existing kernel debug sink,
  physical0x0de00000..0x0de00fff. Each event includes a cycle stamp and warm-reset
  generation. No speculative instruction logging or firmware patch is involved.
  Historical firmware runs emitted genuine kernel/application text through this
  sink (kernel503243a8, mapped from VA59000000). Current hardware output remains
  unverified and depends on the firmware's debug enable flag.
* A256-entry FIFO never backpressures the phone. It drops excess bytes and
  counts them. Records pack up to12 bytes, ending on newline, an empty-FIFO gap,
  or reset-generation change. A1024-record DDR ring retains at most12,288 bytes
  of text. Reader overruns and producer drops are reported separately.
* Periodic snapshots at4 Hz include24 existing monitor DWORDs, the406-halfword
  NGD recorder (bus/fetch faults, recent trace, panic report and save-error bits),
  clock rate, reset generation and build-date tag. Fetch PC is not retirement PC.
  These are observations over a short capture window, not an atomic CPU/process
  state dump. Existing trace insertion pauses for about865 clocks during capture;
  committed text capture continues independently.
* Intended new embedded RAM: one256x32 snapshot M10K plus two for256x64 FIFO.
  No new asynchronous register-array memory. Actual fitted ALM/M10K/timing costs
  are unmeasured. Snapshot traffic is approximately4 KiB/s before transport
  overhead; text uses32 bytes per up-to12 characters plus header updates.
* Periodic snapshots directly own the registered NGD read port; the diagnostic-
  disk exporter and its arbitration were removed on2026-11-13. Warm CPU reset
  preserves transport/history. Cold transport reset
  starts a new session, seeds sequences from retained DDR and clears mailbox seals.

Visual diagnostics remain enabled for the first hardware comparison.
`ngage_mister.DEBUG_VIDEO=0` provides a phone-only pipeline for the subsequent
renderer removal, after DDR readback is demonstrated. It is not selected in
this qualification build. No arbitrary external-SDRAM dump, EKA1 process-list
parser, SVC argument decoder or new guest debug enable is implemented.

## Memory and reader

SSH checks of the installed Linux established `mem=511M memmap=513M$511M`:
Linux System RAM ends at0x1fefffff. The core's ROM/C:/PMM occupy
0x30000000..0x3180ffff. The diagnostics use the existing unused64 KiB gap
0x313f0000..0x313fffff, between loaded ROM and C:, without expanding that span.
The framework's fixed video/ALSA ranges and observed Main mappings do not
intersect it. This is reservation evidence for that installation, not a general
allocation API or proof for a different MiSTer Main/memory layout.

Linux `/dev/mem` reads succeeded at the core addresses. The loaded RBF had no
new diagnostic signatures; **end-to-end FPGA-to-Linux capture requires a new
RBF and remains a hardware gate**. No core reload, reset, OSD write or remote
memory write was performed. Credentials are not stored in tools or evidence.

From the project folder, after loading the new RBF:

```sh
ssh root@192.168.1.176 'python3 - --follow' < tools/ngage_runtime_diag.py > scratch/ngage1-runtime.jsonl
```

The helper runs through SSH stdin, opens `/dev/mem` read-only with synchronous
mapping, reads only the guard area and emits JSONL. It does not need any mounted
image, background save or manual flush. Stop with Ctrl-C. `text` events contain
both decoded text and exact `raw_hex`; `snapshot` events contain named monitor
values and complete NGD halfwords. `session`, `producer_drops` and `reader_gap`
events identify session changes and losses. A missing signature is reported,
not decoded as valid data. The default polling interval is250 ms. It can also
read an offline64 KiB guard dump with `--file path`.

A DDR/arbiter deadlock can prevent new records; the last committed records may
still be read by Linux. Ring contents are volatile and overwrite; SSH capture
must be running to retain a long boot. Firmware crashes that emit no sink text
can still be investigated through the periodic PC/fault/panic snapshots.

## Wire format (little endian)

Text header at0x313f0000, eight DWORDs: magic0x3154474e (`NGT1`), version1,
capacity1024, last committed sequence, dropped-byte count, first sequence of
this FPGA session, clock Hz, record size32. Records atBASE+0x100, indexed by the
low10 sequence bits, each eight DWORDs: sequence, first cycle, generation in
bits31:8/length in bits7:0, three payload DWORDs, dropped count, seal
`sequence XOR0x4354474e`. Length1..12. Seal is invalidated before replacement,
written after payload, and then the header head is published. Sequence0 and a
zero-valued seal are skipped. Tests also use an8-record ring to exercise wrap.

Snapshot slots at0x313ff000 and0x313ff400, each256 DWORDs:

| DWORD | Contents |
| --- | --- |
|0..7|magic0x3244474e (`NGD2`), version1, sequence, clock Hz, capture start/end cycle, reset generation, NGD count406|
|8..31|24 existing monitor values, in `tools/ngage_runtime_diag.py:NAMES` order|
|32..234|NGD halfwords0..405 packed low then high|
|235..254|reserved zero, except240/241 low/high64-bit build-date string tag and242/243 save status/LBA|
|255|seal `sequence XOR0x4344474e`|

Each snapshot invalidates its seal, writes payload, and commits seal last.
Host reads seal before/copy/after and checks sequence, signature and version;
no Linux write handshake is needed. The reader suppresses duplicates and rejects
torn records. Sequence arithmetic assumes less than2^31 records of separation.

## Verification and next gates

`tests/phone/diag_ddr/run.sh` runs bounded Verilog2001 fixtures with the actual
registered NGD recorder, variable readiness/response delay, loader overlap,
12-byte batching, saturation/drop accounting, manual-export capture exclusion,
warm reset and cold reload. It exercises1024/8-record rings, physical64-bit DDR
lane/address conversion through the actual streaming adapter, collision-poison
RAM, and optionally the existing Intel model with `ALTERA_MF=path`. The host
reader checks exact writer output, duplicate suppression, ring loss and torn
text/snapshot handling. Existing diagnostic recorder/raster tests and production
top structural elaboration pass. Evidence: `docs/evidence/ddr-diagnostics-2026-11-12.json`.

Next: fit/timing review, load a new RBF, start SSH capture early, verify signatures,
build tag, increasing sequences, runtime text availability and reset generations.
Only then disable visual rendering and measure its saved area. No build/CI
monitoring or hardware boot run was started here.

## Deferred persistence and video defects

User reports Background save stops boot after1–2 seconds at FETCH00000000, and
manual flush at screensaver leaves SAVING=1 for a long time. Previous resets may
have interrupted saves. Compared card copies show1092 changed boot0 sectors and
two PMM sectors, plus a new StarterMonLog entry. This proves partial persistence
only. Neither successful drain nor the cause of a stuck save has been established.
SAVE indicates mounting; SAVING and SAVE BUS should eventually clear, SAVE ERR
should remain0. The phone-only view has no clear save indicator.

Donor reviewed: `/Users/andreabogazzi/develop/ngage2`,542300b,
`rtl/mister/flash_save.sv` and `rtl/mem/ddram_flash.sv`. It queues first-dirtied
sectors, clears a sector's dirty bit when its DDR snapshot is accepted, preserves
subsequent marks for another pass, reads64 DDR beats per512-byte sector, holds
`sd_wr` until `sd_ack`, and waits for ACK deassertion before advancing. It schedules
saves after100 ms quiet/2 s maximum age, and retains save state across CPU resets.
Our ordered path intends the same ownership/order guarantees, with1 s quiet/5 s
age and C:+PMM support; changing delays alone would not establish a fix. Donor
saves only CS1 because of its QD firmware; dropping NEM-4 PMM persistence is not
justified by that. Donor has no timeout in that write ACK wait: it can wait
indefinitely too. Neither implementation's existence proves the board handshake.

After DDR qualification, reproduce with concurrent production ROM fetch/D1/D2/
bulk persistence and HPS latency, capture scheduler/raw-save state and last
completed sector, and compare ACK ownership/OSD behavior. Do not mask the fault
by extending timeouts without evidence. No persistence RTL changed in this pass.

Also queued, unchanged: HDMI scrambled lines; CRT left shift and missing first
one/two columns or pixel/window misalignment. Startup/runtime diagnosis takes
priority over these display defects.


## Save progress extension

Snapshot DWORD242 is the passive save state and243 the current file LBA.
State bits2:0:0 Idle,1 Load start,2 Load wait,3 Flush wait,4 Failed.
Bit3 selects slot0 C: /1 PMM. Bits4..28 respectively:
mounted, saved, saving, error, manual batch, manual pending, queue pending,
queue flushing, queue sector valid, flash quiescent, bridge ready, bridge done,
bridge error, host ACK, host read request, host write request, DDR request,
DDR ready, DDR done, queue error, queue fault, bundle verified, autosave enabled,
autosave paused, dirty event. Bits31:29 zero. The reader exposes named flags.
This expands reserved words without changing version1 or existing NGD layout.

The save investigation is now active, with a verified write-back failure/CPU
reset isolation fix. The earlier deferred-save notes above record the initial
checkpoint; see [current save findings](save-blockers-2026-11-12.md).


## First hardware DDR readback,2026-11-12

User loaded the diagnostic RBF. Read-only SSH capture successfully retrieves
NGT1 text and sealed NGD2 snapshots directly through Linux /dev/mem; build date
261112,78 MHz. This qualifies the FPGA-to-Linux path on the tested installation;
exact RBF commit is not encoded. No reset, key, OSD, save or memory/media write.
25 s bounded follow yielded71 valid snapshots; sequence advanced96 (24 s of
snapshot cycle time), zero producer drops/reader gaps. Sampling can skip frames.
The fetch PC remained in the fatal handler/literal/speculative vicinity, CPSR
600000D7 (Abort mode), reset generation0. Bus ACK count34879632 and error count13
were unchanged. An isolated sampled PC0 does not establish a reset.

All snapshots retained panic503AD63C/E59FF044/10000000, valid mask7. The existing
special-context decoder identifies exception PC503AD63C and fault address
E59FF044, matching the earlier hardware bad-pointer packet. Existing stock-ROM
analysis maps this to EUser RArrayBase::Count(), `ldr r0,[r0]`. This records the
terminal fault, not its caller/pointer origin; LR/FSR/registers/process inventory
are not exported by this backend. Sticky first fetch fault0C0047E4/reason1 is
historical; no new error appeared during capture.

Retained text is `[0xc0]TRtcQueue::Add: 2[0xc0]TRtcQueue::Add: 4[0xc0]auxstart 100`.
Raw bytes are preserved; no additional text arrived while terminal. Save state
Idle, both images mounted, unsaved queue pending, autosave Off, no flush request,
no save/queue/bridge errors, no HPS/DDR save request active. This is not a test
of saving and does not explain the earlier manual-flush stall. No C:\logs work.

Local raw/decoded captures: `scratch/mister-ddr-live-20261112/`.
Maintained evidence: `docs/evidence/mister-ddr-live-2026-11-12.json`.


## Hardware after working.nga restoration,2026-11-12

User reports further progress after reloading the restored pair.30 s read-only
DDR sample:86 accepted snapshots over29.25 s of cycle time, panic mask0 throughout,
reset generation0, +15,088,164 bus ACKs and no increase from13 historical errors.
Prior Count bad-pointer packet is absent. Save idle, both images mounted,
unsaved queue pending, autosave Off, no save error. No input/reset/flush/media write.

Retained text(1053 bytes) reaches `RAdspServerSession::Construct`, channel counts1/2,
`CSysApAppUi::ConstructL: Start listening`, `TRtcQueue::Add: 5`. It contains repeated
BTLDD CompleteWithError/HCI CBUS sender/receiver ERROR-33. These identify Bluetooth
transport errors, not a proven cause of remaining startup delay. No new text
arrived during the sample. First117 sequence positions of this session were
already overwritten before attachment; this is not a full boot log. Producer
drops0. Most packets hold one byte because the256-cycle gap is shorter than
observed inter-character time; future packet-gap tuning could improve retention
without expanding RAM. No such RTL change made in this inspection.

Sample PCs cluster50327f38..50327fb4, especially50327fa8; sampled bus address
0c120a10 throughout. Exact original ROM disassembly confirms DFC-list dispatch
at50327f48 (head80006bb8), callback50327f7c and scheduling call50327fa8->50329d94.
The firmware explicitly selects mode1b here; CPSRdb is not alone evidence of an
undefined-instruction exception. Active kernel activity is established, useful
UI work or normal waiting versus a pathological scheduler loop is not. Current
backend cannot identify active processes, inspect run queues or read registers.
Do not borrow the other chat's simulated process list as hardware evidence.

Raw, readable text, NGD and decoded files under
`scratch/mister-ddr-after-disk-20261112/`; maintained evidence in
`docs/evidence/mister-ddr-after-disk-2026-11-12.json`.
