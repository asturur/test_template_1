# Original-firmware startup: HDL-only qualification

User selected **strictly unmodified firmware, HDL only** on2026-11-12.
The successful Menu experiment is diagnostic evidence, not completion of this
requirement. Do not integrate an automatic ROM patcher, enable the previous
NOS/BT overlays, rewrite native SIM state, omit RF/ADSP startup tests, change
self-test severity/results, extend ViewSrv deadlines or patch primary checksums.
A synthetic handset identity/card is allowed at the modeled device boundary;
its values and protocol limits must be explicit. Original NOS stays in charge.

## Acceptance

Fresh core load with original audited MCU/PPM service containers; no SSH ROM or
RAM writes, compatibility overlays, exit/DOS/SIM hook injection or guest startup
substitutions. Normal2s/20s deadlines. Native SIM reaches serving through its
own initialization, native RF/ADSP tests finish without registry edits, Phone
idle and Menu open and ordinary input launches an application. Preserve source
firmware hashes before/after and record the exact RTL/build/media identities.

Valid native user/factory data is separate from executable firmware. The PMM
50/1 default in the successful experiment is synthetic policy with unverified
factory meaning. Establish valid PMM initialization/read/program behavior and
restart persistence without silently injecting records into a mounted image.
Do not infer a flash-controller fault solely from a missing record.

## Current source audit

* Production Template explicitly selects TEST_SIM_ENABLE=0 and presence low;
  ngage_test_sim.v is omitted from the selected QIP. Enabling it alone is not a
  readiness fix: historical native firmware remained starting1 after card reads
  and awaited the MTC ready transition. See sim-presence.md for existing traces.
* ngage_simif.v and ngage_test_sim.v are transaction-level hypotheses, with
  passing directed card/FIFO/CEN and board/FIQ tests. They do not establish
  UEM electrical behavior or complete firmware initialization.
* The former ngage_mdi_stub.v consumed and discarded ordinary DSP messages.
  Production now selects ngage_upp_mdi.v and ngage_upp_dsp_peer.v for the UPP
  internal DSP version protocol, qualified below. The legacy stub is excluded
  from files.qip.
* ngage_adsp.v now explicitly marks the separate D550 audio DSP unimplemented. ngage_mjoelner.v and ngage_lrb2.v are
  non-driving component boundaries. Native request routing must identify the
  actual missing hardware owner before modifying any of them. A resource ID is
  not an OS task number, nor proof that a request crosses a particular chip.
* Other-chat CPU/SDRAM/DMA modifications and frozen simulations are independent;
  do not restart/rebuild them or reuse their checkpoints across model changes.

## First executed contracts

`python3 tests/tools/test_native_startup_contracts.py` executes the original
NEM-4 RF and ADSP startup client functions from the audited NOS dump. The ROM
is byte-identical after every call. Allocation, message transport, timeout and
logging leaves are spied; this is a client contract fixture, not hardware proof.

| Client | Original entry | Native request | Timeout argument | Required outcome |
| --- | --- | --- | --- | --- |
| RF ID |516A60C0|resource1B, body0C070020|500|initial return2 remains pending; timeout writes13; reply must satisfy native version checks |
| ADSP |516A6218|resource82, body prefix0E2B00070042; length metadata8|3000|initial return2 remains pending; timeout fails; reply8B result word at+6 must be0, nonzero fails |

The RF fixture validates the native INFO RF-version subblock54 and rejection
cases. Its actual layout for synthetic revision03 is
`0c0800015408000330330000`: one subblock54, size08, string length03,
ASCII03/NUL and padding. Earlier TEST03 input happened to satisfy the small
client predicates but misidentified54 as a character; that interpretation is
superseded. ADSP tests propagate0/1/1234 results and free the original response
exactly once. A timeout does not alone identify its physical cause.

2026-11-12: both native contracts pass. Existing jotego/simulator:arm64 image,
network disabled, passes card reference/FIFO/overflow/CEN checks and all four
board presence/card combinations. Log:
`scratch/hdl-native-startup-20261112/sim-baseline.log`. No default HDL or board
state change was made by these tests. Existing patched Menu session preserved.

## Implementation order and dependencies

1. Identify native request routing and hardware consumers for SIM startup,
   RF version and ADSP diagnostics using original handlers and MMIO traces.
   Retain original instruction bytes. Replay the corresponding native driver
   against HDL; unknown transactions remain explicitly unsupported.
2. Correct SIMIF/card behavior at the UPP/UEM/card boundary, including reset,
   ATR, byte ownership, interrupt acknowledgement and requested EF metadata.
   Test reset/absence/presence, stalled commits, 78/104MHz scheduling, repeated
   initialization and native link-layer completion. Determine the missing MTC
   transition from its producer; never force the firmware state/event.
3. Implement the identified RF/ADSP control/diagnostic exchanges in the proper
   chip module. A protocol model may suffice; executing a DSP is not assumed.
   Test actual native sender/receiver, packet ownership/lengths, timeout, bad
   response, reset, backpressure and diagnostic failure propagation. Do not
   return success unconditionally or bypass the native test.
4. Replace Bluetooth timeout compatibility with the identified LRB2 interface
   behavior; verify native driver reset/start/query and bounded completion,
   preserving its component boundary. Fake carrier/registration is a separate
   network-model requirement, not established by a displayed name or wallpaper.
5. Qualify normal-deadline Phone/Menu with valid captured native C/PMM first,
   then cold/erased initialization separately. Verify native PMM read, append,
   1->0 programming, old-record retirement and durable C/PMM save/reload. Keep
   firmware immutable; initialized disks alone do not prove the clean path.
6. Select only qualified models in production, measure area/BRAM/timing and run
   a cold-board boot without patch tools. Keep78MHz PLL; design toward104MHz.
   The former SIM card cost440.7 attributed ALMs and removed dual overlay
   engines677.7 ALMs/14 M10Ks; avoid blindly reinstating those implementations.

No HDL-only Menu success is claimed yet. Native transaction ownership and the
SIM readiness producer are the current unresolved implementation boundaries.

## First HDL corrections (2026-11-12)

SIMIF status is W1C, but the former TX-complete phase transition checked only
pending status[3]. A zero/unrelated status write therefore entered RX and raised
status18 even though TX-complete8 was not acknowledged. The new board regression
reproduces exactly `got18 expected8`; requiring both pending status[3] and written
din[3] fixes it. All four card/presence combinations, the554-operation card
reference,600-response FIFO stress/overflow/reset and32-clock CEN tests pass.
This is a controller correction, not proof that the whole SIM initialization
or native serving-state transition is solved.

Native CBUS function503822BC polls the status halfword before programming CFG,
command and payload. The former controller rejects status reads unless stage3
(completed), so the first idle poll is an invalid transaction. Status is now
readable throughout the modeled transaction: reset-idle0 and completed3 return
DONE400; assembling1/2 leave it clear. Command/payload validation stays active.
The new regression fails before the fix at the first reset-idle read and passes
afterward, including intermediate/not-done and completed states. Both power-up
profiles, existing RTC/alarm/C++ timing references and33 committed peripheral
response/hold/reset cases pass after the changes.

`test_native_cbus_contract.py` executes the untouched original client, confirming
idle-poll ordering, CFG15 for16bits, chip5/logical-register27 encoding as wireA6,
payload and completion poll. Its HAL leaves are spied and ROM stays identical.
A separate `tests/phone/native_cbus/` runs the actual driver/HAL instructions on
the HDL CPU and controller: wait0 passes in1220cycles; wait3 in1832cycles.
The fixture uses original code and HAL, without transport/driver substitutions.
It aliases the observed HAL virtual peripheral window at the testbench boundary;
MMU and physical CBUS/LRB2 signaling remain outside that fixture.

Recovered earlier original-firmware evidence is important: the native ADSP
self-test request0E2B traversed NOSDRIVER to Symbian process adspserver/Main,
not a demonstrated direct MDI mailbox request. Do not implement a mailbox0x8B
response solely from the self-test client's packet. The native Info proxy also
requires tracing its actual provider. Current EInfoServer code is at50995C14;
the older extracted executable header names50991F64. Use service-ROM identity,
not stale extracted addresses, for further native fixtures.

These changes are local source/tests only. No new RBF, fit/timing or complete
unpatched board boot is claimed. The user's patched phone/MMC session is left
under their control. MMC is explicitly parked behind boot: the mounted Sonic N
image validates and is known working on the donor; a newly expanded authored
CPU full-sector test fails at stage7, providing a local reproducer for later.


Reproduce the focused checks (existing simulator image only):

```sh
python3 tests/tools/test_native_startup_contracts.py
python3 tests/tools/test_native_cbus_contract.py
sh tests/phone/native_cbus/run.sh
# Inside jotego/simulator:arm64, from /work:
sh tests/phone/cbus/run.sh
sh tests/phone/cbus_timing/run.sh
sh tests/phone/simif_board/run.sh
sh tests/phone/card_fixture/run.sh
sh tests/phone/peripheral_response/run.sh
```

Evidence: [native-startup-hdl-2026-11-12.json](evidence/native-startup-hdl-2026-11-12.json).
These short runs use separate output directories and preserve all long-run
checkpoints. No new complete-boot simulation, CI monitoring or board reload.

## Native RF provider and UPP internal DSP link (2026-11-12)

Recovered native chain: Info_SrvMgr5164AE78 handles1B/07 flag20, requests
F1/A0 body20A00200 via5164B3A4; native platform type1 selects resourceF1.
Original receiver515920D0 acceptsF1/A1 body20A10103, converts revision3 to
its own decimal string03 at cache80009D3C. Original INFO builder5164C3EC
constructs subblock54; unchanged startup function516A60C0 passes03 and fails04.
SW version uses40A00100 ->40A105/HDL01, with cache80009D38.
Device identities are explicit synthetic data, not changed instructions or
prewritten guest globals. tests/tools/test_native_info_version.py executes the
receiver, builder and pass/fail test; ROM remains byte-identical after each call.

Original TX task514C4868 and ring writer515BF550 establish big-endian Phonet
length fields, halfword byte swapping,250-halfword wrap, pointer publication
and release. tests/tools/test_native_mdi_contract.py executes both unchanged.
M2D is0C100000..1F3, D2M1F4..3E7. Pointer words3E8/3EC contain
producer low16/consumer high16. Control0C14B004 low0500 enables the link.

Production ngage_upp_mdi now owns this UPP internal link, separate from D550.
It uses one8192-bit true dual-port RAM, registered CPU reads, streaming packet
parsing, full-ring backpressure and publication after the last reply store.
IRQ9 denotes M2D consumption; IRQ10 D2M publication. The previous announcement
is retained; only native F1/A0 RF/SW version queries receive answers. Unknown
requests remain unanswered, malformed pointers quarantine the engine and reset
clears ownership. ngage_upp_dsp_peer contains the explicit03/HDL01 identity.
This is a transaction-level protocol model, not DSP execution or pin timing.

Focused peer and ring tests pass routing, framing, unknowns, reset, wrap,
natural saturation, pending-response release and publication ordering.
Actual HDL CPU runs unchanged515BF550/515BF474/515BF65C/515BF7D8 driver code
against the new controller: wait0=4913cycles, wait3=7367cycles. Authored setup
aliases the observed MMIO window; it does not qualify MMU or full boot.
Integrated board CPU regression passes SIMIF, LCD queue/DMA, faults,
diagnostics, IRQ/FIQ, SDRAM waits and live UPP shared-RAM DMA. Four board SIM
profiles and33 peripheral response/hold/reset cases also pass. All code remains
Verilog2001 and uses the pinned formatter. No Quartus area/timing result yet.

Commands: tests/phone/upp_dsp_peer/run.sh and upp_mdi/run.sh inside the existing
simulator image; tests/phone/native_mdi/run.sh and mister_board_cpu/run.sh on
host launch that image. Local logs: scratch/hdl-native-startup-20261112/.
No fresh RBF or unpatched Phone/Menu success is claimed. Separate D550 ADSP,
native SIM readiness, Bluetooth and durable PMM qualification remain open.

## External ADSP control and serial transport contracts

Native ADSPCTRL module in this exact service ROM is510E9294, DoControl510E9734.
The12 cases of tests/tools/test_native_adsp_controls.py execute controls0..5
at both input levels with original HAL instructions, spy only the CBUS callback,
and assert register ordering, masks, stack and unchanged ROM. Controls4/5 use
CBUS device1, logical0F/10,8-bit fields with masksF0/20. These are not DSP
mailbox registers. The original CBUS table maps them to native wire2F/30;
logical register numbers must not be used directly as CBUS command bytes.

Native EUART1 module510E83D4 identifies its client as ADSPComm and binds
FiqCTSI_FIQ. tests/tools/test_native_euart_contract.py executes its unchanged
TX510E8BE8 and RX interrupt510E8D58 with actual HAL load/store instructions.
TX count-minus-one is written to0C15055A, data bytes occupy high8 of the
halfword at0C150554. RX byte high8 is read from0C150556; FIFO producer/
consumer nibble comparison uses0C150562. RX status8 is acknowledged through
0C1500BA. The fixture checks three nontrivial bytes both directions and ROM
immutability. A first RX probe used the TX counter055C incorrectly; corrected
by decoding the original literal at510E8DF0. It must not be propagated to HDL.

At the2026-11-12 checkpoint, production only supplied generic storage and a forced TX-idle bit for
this UART region. It does not consume serial TX or deliver DSP serial RX.
Therefore the external ADSP native path cannot be repaired by replying in the
UPP internal MDI ring. Remaining work is the native ADSPComm/MADI framing,
shared CTSI interrupt ownership and device-side diagnostic behavior. The control
and serial fixtures establish the interface; no successful ADSP self-test or
physical pin mapping follows from them. Schematics A-3/A-8 inspected locally;
keep GPIO bit-to-net assignments unverified until the connection is established.

Additional boundary checks pass:132 retained ownership pairs, exhaustive regional
overlap/lane/config cases, sparse cancel/overflow/trace exclusion and warm/cold
retention. The wrapper fixture's former16-cycle limit was stale: the existing
committed BRAM sparse table can probe64 slots on a full-table miss. The timeout
is now66 (64 probes plus capture/result), preserving all error/data assertions.
Initial failure at0DFF0220 had mdi_claim0/mdi_ready1 and d_ready0; with the
proper bound the maintained wrapper test passes. No sparse RTL was changed.

## EUART HDL transport implementation and native CPU qualification

ngage_upp_euart.v now implements native TX/RX byte lanes, count-minus-one
batches, separate synchronous16x8 BRAM queues, RX producer/consumer nibbles,
backpressure, bounded prefetch and mask/ACK/reset behavior. RX pending follows
owned unread data rather than being erased by the ISR's early ACK. Unknown DSP
services are not answered. At that checkpoint it was not selected in production files.qip;
shared CTSI and external device integration remain required.

The focused test passes held/uncommitted accesses, TX16-byte saturation and
wrap, RX15-byte saturation and wrap, masked/completed IRQs, RX ACK-before-drain,
empty reads, flush priority and reset. Native tests/phone/native_euart executes
original TX, RX IRQ, HAL and poll code on the actual HDL CPU: wait0=7064cycles,
wait3=9834cycles. Original ROM/IAT bytes remain untouched. Only the caller,
logical-channel callbacks, RTOS flag, IRQ invocation and byte loopback are authored.
The first native test exposed a missing fixture clock-control5814F008 used by
the normal TX-idle path; retaining that register fixed the fixture, without
modifying driver/HAL instructions.

Area/timing gates: two explicitly selected M10K FIFO instances (256 payload
bits total), plus controller state/configuration registers. This is a design
inventory, not a measured fitter result. No wide asynchronous queue read mux,
DSP interpreter or second CPU is introduced. Queue latency is registered and
bounded; real baud/serial timing remains unmodeled. Keep78MHz PLL;104MHz target.
Before the next FPGA build, renderer retirement is separately committed as
c41d620. Diagnostic video/font are removed, DDR observation paths remain;
see diagnostic-video-retirement.md. No RBF, timing closure or unpatched Menu
success is claimed by these focused tests.

ADSP firmware inventory correction2026-11-12: the existing Phoenix package
includes E403A400H450.USB, explicitly selected by NEM_4.ini AdspFile. This is
not merely the ARM host driver. See firmware-inventory.md for size/hash and
identical copies. Decode the08A5 container and establish D551 mapping next;
a raw external-DSP ROM is not yet decoded, but the update file is already here.

## 2026-11-13 native SIM and diagnostic operation checkpoint

See [sim-adsp-native-progress.md](sim-adsp-native-progress.md). Original SIM29/37
serving handler/getter/status mapping already supplies the donor completion;
three native cache cases pass. New D550 diagnostic42 and separate N501 reset
transaction model pass78/104MHz tests, but are not selected/wired in production.
Original packet checksum/sequence tests pass (synthetic input descriptor), as
do unchanged RF/ADSP startup clients and all12 ADSPCTRL control cases. Shared
CTSI, complete device framing and native SIM/MTC-ready remain unresolved.
No complete native boot, fit/timing or hardware result is implied.

## 2026-11-13 completed production UART/CTSI boundary

EUART is now selected and connected through the board byte interface. Actual
CPU FIQ26 with unchanged TX/RX/HAL/poll and simultaneous SIM/UART registered
ownership tests pass. External D550 peer remains explicitly inactive; this is
not an unpatched boot fix. [Scope/results](euart-production-integration.md).
