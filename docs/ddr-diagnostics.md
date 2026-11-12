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
* Manual NGD disk export and periodic snapshots serialize use of the registered
  NGD read port. Warm CPU reset preserves transport/history. Cold transport reset
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
|235..254|reserved zero, except240/241 low/high64-bit build-date string tag|
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
