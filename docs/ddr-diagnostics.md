## 2026-11-20: Bomberman session hardware reset

Physical MiSTer with DDR build tag `261120`. The pre-crash screenshot shows
Bomberman Stage 1-1, and the post-crash screenshot shows the Nokia logo.
DDR text records shutdown of threads 74, 135 and 61. The raw NGD ring retains
the subsequent `hw_reset_generate` diagnostic on the NOS trace port.

The last advancing snapshot is sequence 541887299. Sequence 541887300 shows
the CPU at Thumb PC `0x514c11b2`, CPSR `0x200000fb`, with both interrupt masks
set. The last acknowledged transfer is to physical `0x0c150000` with the
halfword duplicated on the data bus as `0x00040004`. The fetch count keeps
advancing from the same PC while acknowledgments stay at 1317654201. Reset
generation stays at zero, the bus-error count stays at its pre-existing three,
and the kernel panic mask stays clear. The retained NGD fetch fault
`0x0c0047e4` is present in the first captured snapshot, before the game run.

The verified stock NEM-4 4.03 image identifies the sequence as a halfword write
of `0x0004` to virtual `0x58150000`, followed at `0x514c11b2` by a branch to
itself. The UPP routes the accepted halfword to `gpio15_ram`. The phone-reset
gate in `Template.sv` receives only the MiSTer framework reset, OSD Reset and
the mapped controller reset button. Thus the requested reset has no modeled
effect on the running core. The alternate firmware path for reason `0x0c`
writes `0x0008`; the observed `0x0004` is shared by multiple callers and
cannot identify the reason. The actual NEM-4 reset scope and timing require
separate qualification before adding an RTL side effect.

The user reports a bomb exploding shortly after starting gameplay, with
previous instances after two ordinary explosions. The three
`SHUTDOWN: App with ThreadId … has exited` messages belong to stock
`EikSrv.dll`. The last sampled button was 14.75 seconds before the park,
with no power-key bit seen at the 4 Hz snapshot rate. This does not rule out a
short input. The original capture does not contain the reset caller or
reason. A volatile repeat uses guarded probes at the NOS reset argument
write (`0x514c1144`) and kernel `Plat::Reset` entry (`0x50324dc4`).
The probe retains the original checksum check and passed 42 synthetic
ARM/Thumb ABI cases. The repeat uses the same fitted RBF and Bomberman card,
with background save disabled for the instrumented boot.

The first controlled repeat reproduced the park after a 200 ms keypad-5 press
and a Down input in Stage 1-1. Shutdown logging began 0.105 seconds after the
keypad-5 sample and before the sampled Down input. No explosion frame was
recorded. The firmware observer emitted `@N:00000015:514c2177`, identifying
`MTC:PO:HW_RESET_POWER_OFF_RTC`. There was no `Plat::Reset` probe record.

In stock firmware the RTC shutdown callback queries UEM logical register
`0x15` (CBUS `0x35`) and immediately returns true when bit 3 is high. The
fitted UEM read unconditionally ORs in `0x0008`, so clearing the stored
alarm status cannot make that read low. An offline run of the original
Nokia instructions with controlled service replies reproduces reset
`0x15` with bit 3 set and no scheduled alarm. With bit 3 clear, the no-alarm
and six-second-away controls choose ordinary power-off, and the alarm
four seconds away still chooses the RTC reset. This identifies the false
RTC result once the firmware enters power-off. It does not establish
what initiated the shutdown.

The expanded repeat reached Bomberman after confirming `1P game`. Its first
park was snapshot 541896708, two seconds before the only subsequent
keypad-5 sample (541896716). The game had already rendered a bomb on its
own. Thus a manual bomb press is unnecessary to reproduce the symptom.
Before the park, the stock path logged these probe records in order:

| Relative to park snapshot | Probe evidence |
| --- | --- |
| −2.513 s | `@T:00000100:51599ff7`: MTC transition with target state 0, reached via the MTC internal event handler for type `0xf0`, subtype `0x0d`. |
| −1.277 s | EikSrv starts logging the shutdown exits. |
| −0.060 s | `@S:00000001:514c6599`: MTC state machine calls the power-off routine. `@R:514a4d44:514c2163`: the routine calls the expected RTC wrapper. `@N:00000015:514c2177`: it selects the RTC reset. |

The MTC event handler completes an in-progress transition. The requester
that started it is outside the recorded probe points. The original trace
and both repeats park on the same GPIO write with reset generation zero.
The expanded probe passed 54 offline continuation/ABI cases before use.
After the repeats, the same fitted core and card were reloaded, the full
stock ROM hash was verified, and the CPU advanced with the original
Background save On setting. No production fix was installed.

Local evidence: `scratch/crash-debug/ddr-20261120T075330Z.jsonl`,
`scratch/crash-debug/screen-20261120T075910Z.png`, and
`scratch/crash-debug/crash-20261120T075942Z.png`. Instrumented evidence:
`scratch/crash-debug/reset-observer/repeat.jsonl` and
`scratch/crash-debug/reset-observer/upstream.jsonl`.
[Original-code RTC branch controls](../tests/historical/bomberman-reset-20261120/rtc_branch.py).
[Rebuild the observer](../tests/historical/bomberman-reset-20261120/prepare.py).

### Bomberman binary and UEM alarm

Read the installed MMC without changing the running core. Its SHA-256 is
`1bcb220afea6e7b593c8aad928de0d7b9974848febabc1a0c2573395855a3a60`. The
FAT12 audit passed, and the extracted `6R29.APP` SHA-256 is
`2ae0a18fc258c10a9eeb9c3d7d8abc9d6a7b0afff90207be9fef1b0806a56cee`.
Its code embeds version 1.0.2. The app and the card's GameComms, GameUtils
and LightDrv are uncompressed ARM E32 images. Each import block's ordinal
list matches the import slots following the text section. Local ARM listings
and import tables are under `build/bomberman-analysis/`. Listing addresses
use the E32 link base `0x10000000`. Embedded tables can appear as instructions
in a linear listing.

- The app's direct `CEikAppUi::Exit` calls are at `0x10005d38` and
  `0x10005dc0`. The latter is reached for error `-4` (`KErrNoMemory`).
  The checked imports contain no `UserSvr::ResetMachine`, `UserHal::SwitchOff`,
  `HAL::Set` or EikSrv shutdown entry. This bounds the direct imports only.
- Bomberman uses System Agent queries and notifications. Its GameUtils helper
  queries battery/charger UIDs `0x100052d3` and `0x100052c9`, and its
  LightDrv calls `RDosLights::SwitchLights`, which sends DOS-server IPC
  `0x258` in the inspected NEM-4 DSClient. GameUtils also
  tries to load the optional `z:\system\libs\vbrdrv.dll`, which is absent
  from the inspected NEM-4 ROM directory. The preserved Sega Rally
  `6R12.APP` imports the same media stream library and has no GameUtils,
  LightDrv or System Agent dependency.
- The mounted Bomberman image has an unused `ENGAGE_ENGAGE_ENGAGE!` import
  string and two active import blocks naming the same audio library and
  ordinal. The main constructor reaches the real audio import from
  `0x100001d8`. The other block's apparent thunk at `0x1003bca0` begins
  with `bx lr` and returns immediately when called from `0x10000c28`.
  These are properties of the tested image. There is no original
  comparison image to attribute that stub or connect it to the shutdown.

The RTL candidate removes the constant bit from CBUS register `0x35`.
Firmware can acknowledge bit 3 by writing `0x0008` to that register.
The regression checks the clear before and after the staged startup alarm,
the independent power-key bit, and a later periodic IRQ with no new alarm.
The old RTL fails at the first read after acknowledgement (`0x0018` versus
`0x0010`). The staged boot alarm remains an explicit approximation.
Both CBUS power-up profiles, board IRQ routing, registered peripheral
responses, 78/104 MHz clocks, and all four native RTC CPU/HAL cases passed.
The candidate has not run on MiSTer.
There is no measured evidence associating the game's lighting, battery
queries, modified import thunk or audio paths with the upstream MTC request.

## 2026-11-16: Passive memory-path wait observations

Existing reserved snapshot words245..251 carry router and NOR state. No snapshot
size, wire version, capture period, FIFO or live-path state changes. Older builds
remain readable; `memory_path` appears only with all three explicit markers.

Word245: marker4D in31:24; line FSM23:21; memory owner20:17; owner-valid16;
flash-issued15; code/user pending14/13; code/user idle12/11; code backing
valid/ready/done10/9/8; user backing valid/ready/done7/6/5; retained line/user
response owner4/3; line request/ready2/1; WB cycle0.
Word246: CF marker31:24, C: state13:12, operation11:9, unlock8:7,
autoselect6, program5, erase-armed4, erase-pending3, polled2, valid1, write0.
247=user backing address.248..249=64bit code state, CE marker63:56;
target40:39, chip38:37, operation36:35, state34:33; three11bit die states32:0.
250=code backing address;251=requested physical line address.

These are periodic observations, not an atomic transaction trace. State2 means
WAIT_MEM and1 ISSUE in each NOR controller. C: operations0=read,1=program-read,
2=program-write,3=erase-read,4=erase-write. The local line FSM0=idle,1=ROM issue,
2=ROM wait,3=RAM issue,4=RAM wait. New physical capture remains pending.

## 2026-11-14: Passive D550 and SIM observations

CPU_FLAGS bit31 marks the new status extension, bits30:25 remain zero and
bits8:0 retain their previous definitions. Bits24:9 contain BRINGUP_STATUS:
0..3 D550 state,4 active,5 link-ready,6 clock-ready,7 enabled,
8 diagnostic42 accepted,9 completed,10 result zero,11 native positive reply ACK,
12 SIM overflow,13 busy,14 RX-valid,15 model presence. The reader emits a
`bringup` object only with the extension marker. Four milestone registers are
passive, never stall the CPU/protocol, survive device clock gating and clear on
phone reset. A new accepted42 clears its prior completion/result/ACK flags.
Successful UART ACK does not prove NOS36 completion; keep that distinction.
No new snapshot memory, format length, graphics or firmware instrumentation.

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
|235..254|reserved zero, except240/241 low/high64-bit build-date string tag and242/243 save status/LBA,244 tagged queue state|
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

Display follow-up2026-11-13: CRT missing left columns now has a reproduced
RGB hold bug and an HDL correction; see [crt-pixel-hold.md](crt-pixel-hold.md).
Hardware confirmation, CRT centering and HDMI scrambled lines remain pending.


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

Word244 is an optional queue observation, recognized only when bits31:24 are
0x51. Bits23:9 are the existing15-bit queue count; bits8..2 are initialized,
queue fault, flush error, flushing, in-flight, mark pending, head ready.
Bits1/0 latch the first overflow/invalid-sector causes until cold reset.
The reader emits `save_queue` only for that marker; old zero-filled snapshots
remain compatible. Two sticky FFs are added; count and other flags are wired
from existing state. No new RAM/counter or guest bus stage is added.
The flags are observed during the snapshot, not an atomic per-fault trace.
See [confirmed board queue fault](save-queue-fault-2026-11-13.md).

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

## Host reader follow-up —2026-11-13

Dense software probes exposed reader gaps despite zero producer FIFO drops.
The host reader previously sealed all1024 slots on every poll over uncached
/dev/mem, then slept250ms. It now reads only slots in the unread published
sequence window and polls every20ms. Seal/session/overwrite checks remain;
idle polls touch no text slots, one new record touches one. Writer-output,
torn-tail, gap, reserved-sequence and32-bit-wrap tests pass. Minimal hardware
profile captures have no reader gaps; the same dense-stream repeat is pending.
A late attachment can still report an initial backlog gap. Do not equate zero
producer drops with lossless capture, and reject latency pairs crossing gaps.
See [Phone investigation](phone-profile-startup.md). No FPGA resources added.


## Compile-time removal — 2026-11-15

The entire DDR runtime recorder is opt-in: `ENABLE_DEBUGGER=0` is the source
and CI default; compile with `ENABLE_DEBUGGER=1` to retain it. The build action
has an unchecked **enable_debugger** checkbox. `tools/set_quartus_debug.py` writes
the numeric Quartus macro and adds `enable_debugger`/`debugger_macro` to existing
build-info metadata while preserving the seed/commit/run identity.

The off hierarchy contains none of `ngage_debug_monitor`, `ngage_diagnostics`,
`ngage_diag_ddr`, `ngage_diag_text_ddr` or `ngage_diag_loader_port`. It also removes
the observation sample registers, committed-text capture and diagnostic DDR
arbiter path. Firmware loading retains an equivalent single-outstanding DDR
write path. The functional ADSP startup-test responder remains: it is required
by the phone and is unrelated to runtime debugging. Video is unaffected.

Both top configurations elaborate. The real loader-only block matches the old
loader handshake over5000 randomized clocks, including reset and accept/done
priority. CPU/MMC fixtures pass in both configurations with identical normal
169107cycles/4reads and CPU-Hold169521cycles/5reads; the enabled production board
fixture retains fault/panic/SIM/LCD/DMA/IRQ/FIQ coverage. This does not measure
real-board DDR contention: snapshot traffic (~4KiB/s plus text/header writes)
shares memory with firmware reads when enabled. There is no direct CPU stall
stage, but contention and area/fanout may affect performance. No measured native
score or fitted ALM saving is claimed yet.

Old records can remain in DDR after an off build; a reader finding historical
bytes is not proof of an active debugger. Hardware diagnostic sessions require
a build explicitly compiled with the checkbox enabled. Previously dispatched
c21dff7/run43735997597 predates this flag and cannot be changed by it.
