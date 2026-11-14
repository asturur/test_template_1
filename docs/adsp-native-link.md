## 2026-11-14:7e893c8 timing passes; untouched ADSP42 round-trip observed

Build43552422501/seed44 succeeds:38,065ALMs/91%,508M10Ks/92%, setup+0.059ns,
hold+0.246ns at unchanged78MHz. D550192.0ALMs/190registers/zeroRAM-DSP;
synthetic card504.5ALMs/215registers/oneM10K. RBF SHAe95f40e9... deployed
without backup; original88fd.../Run/save-Off/C4a75.../PMM71189... verified.
180s untouched control:720snapshots/no gaps/reset/panic/first data fault or
SIM overflow. Passive ADSP42 accepted/completed/result-zero/positive native ACK
all become true without any firmware observer. This proves the transport
round-trip on original code; NOS36's stored result is not directly recorded.
Screen Nokia, then blank after Menu; key40 positively sampled. No usable UI yet.

Fresh-Hold MTC/assert-only observation is being prepared at
scratch/sim-card-native-observation-20261114 to read native SIM state and final
NOS test array, with no replies/state/deadline substitutions. Do not reload an
active capture. Preserve original-ROM cleanup after observation. No speculative
BT hardware change, no other simulations/PLL/disk changes. Native GENIO20 path
remains a proved missing producer, with reset/status semantics still to qualify.
Build/capture receipts: scratch/sim-card-production-20261114/qualification.json.

## 2026-11-14: Native ADSP pass observed; synthetic-card board build prepared

462ba08 board delivery capture proves original NOS accepts82/8B/result0000,
writes ADSP36=00 and frees its actual response.640snapshots/no gaps/reset/panic.
However completion/assert-only tracing still reproduces unrelated59/02 winning
the shared waiter. Extra UART/dispatcher logging changes scheduling: this is
NOT stable original-firmware boot qualification. No native replies, deadlines,
self-test registry or state were overwritten. Reload removed all probes;
original88fd.../Run/save-Off/C4a75.../PMM71189... verified. See the compact
adsp-board-2026-11-14.json evidence and adsp-native-link.md; no SD backups.

Next selected build connects the existing synthetic no-PIN GSM card at SIMIF,
using fabricated test identity001010123456789. Original NOS still owns card
initialization/readiness; no SIM-ready override, carrier or real registration.
No OSD option added. Four passive D550 milestone bits reuse spare CPU_FLAGS
DDR snapshot bits, together with existing live state and SIM status. They never
feed protocol control/backpressure; enable/clock resets retain history until
phone reset. This allows original-ROM board diagnosis without observer timing.
Expected old card cost440.7ALMs is historical, not this build's measured cost.

Card554-op reference,600-response FIFO/overflow/reset/CEN, all four presence/
selection combinations, shared SIM/UART CTSI/FIQ26,132 board ownership pairs,
ADSP CRC/replay/failure/milestone checks, native CBUS/UART CPU waits0/3 at78/104,
DDR writer/reader and full MiSTer CPU SIM/LCD/DMA/IRQ/FIQ checks pass. Native
104,408/139,536 clock counts are unchanged.177-source/9QIP preflight passes.
The clock script had stale exact-whitespace and removed diagnostic-disk timeout
assertions; corrected the test only.78MHz PLL remains unchanged,104MHz objective.
Build/fit/board SIM readiness and the shared-waiter race remain to qualify.
Logs: scratch/sim-card-production-20261114/. Other simulations untouched.

## 2026-11-14: Hardware qualification and next delivery gate

Build43545934572/seed44 fits37,498ALMs/89%; D550186.8ALMs needed,183registers,
zero RAM/M10K/DSP. Core setup-0.278ns/three CPU cache-fetch paths, no D550 path
in worst1000. RBF SHA8a6eceef... installed without backup. Original-ROM160s
control reaches Insert SIM,640snapshots/no gaps/reset/panic/recorder fault.
Completion/assert-only probe reproduces St_product/DF2 consuming unrelated59/02;
no accepted8B completion. Do not claim native ADSP36 fixed from isolated tests.

A broader HAL UART/CBUS observation proves D0 startup/05, native transport ACKs
and one actual2B/test42 ->8B/result0000 plus host ACK. That capture has a reader
gap and heavy CBUS logging alters scheduling; no latency/absence/boot claim.
It also shows earlier17/4B/1C application traffic currently ACKed without replies.
Original DSP17 handler emits77; other replies remain investigation, not invented.
Reduced-volume UART/native-dispatch/completion/assert capture is ACTIVE at
scratch/adsp-delivery-board-20261114/running.jsonl (160s). Do not interrupt it.
Observation-only hooks are in volatile backing; fresh-Hold/MD5 guards passed,
348writes verified. Automatic Run/save-Off restored. Must reload and verify
original full ROM88fd.../same C4a75.../PMM71189... after instrumentation.
No production HDL change since462ba08, no SIM enable yet, no SD backups/Flush.
PLL78MHz,104MHz design objective and other simulations remain untouched.

## 2026-11-14: Native clock-control chain qualified while build runs

Expanded native_adsp_boot to execute original ADSPCTRL510E9734 controls4/5,
its real CBUS vtable/RMW503820C4, native writer503822BC, original UART and
production peer. Clock-stop/RX-listen/power-up ordering passes waits0/3 at
104,408/139,536 clocks for78/104MHz schedules, followed by original8B decoding
and NOS completion. This changes the fixture only; in-flight462ba08 HDL is
unchanged. Source state remains196+5 bits, no packet RAM/new FIFO.

Run43545934572/462ba08/seed44 was launched02:22:24UTC; the40-minute in-thread
follow-up is active. No CI polling. Deployment/identity script is prepared at
scratch/adsp-board-462ba08/deploy.py. A completion-only + assertion observer
is prepared/tested there if needed after the initial original-ROM board run:
logs native8B/body/result before original free, with no pre-completion logging
or functional/deadline substitution. Fresh-Hold guards and reload cleanup apply.

## 2026-11-14: Production boot-only peer integrated

The previously standalone startup transmitter is now wired as part of the small
production D550 model. This is a useful hardware-build checkpoint; native board
ADSP36=00 and complete Phone/Menu boot remain unverified.

Production has no DSP CPU, interpreter, audio engine, packet RAM or new FIFO.
The D550 peer, serializer, diagnostic operation and codec have196 source state
bits, plus five UEM control-view bits, before pruning/FSM encoding. Fit/STA must
measure actual ALMs. Existing UART queues are reused. The parser drains serial
TX even when disabled/busy to preserve native masked-interrupt drain progress.

Admission requires native ADSPCTRL's power-up profile: CBUS wire2F bitsF0 clear,
wire30 bit20 set, both written, and UART RX enabled/not flushing. UEM exposes
only the five used bits; no whole-register mirror is added. This is explicitly
a transaction-level control shortcut, not a guessed AMA/GPIO reset pin map.
Admission is registered before the peer's synchronous reset distribution.
The test holds the clocks stopped, starts original UART RX, proves no startup
bytes arrive, then releases both controls using the original CBUS writer/table.

The peer sends the recovered startup frames, waits for valid D0/05, checks
framing/address/length/CRC, ACKs valid single-fragment82 traffic, and implements
only the native2B diagnostic envelope. Test42 goes through the existing clock/
flash/codec operation before8B is serialized. Other test IDs return0C; unknown
application messages receive transport ACK only, not invented application data.
No automatic test is excluded and no firmware deadline/result is overwritten.
D551 is a constant boot-profile signatureFFFC from the audited image, not a full
flash loader or executed DSP firmware. N501's reset1E00 transaction is separately
modeled and wired on the board. PCM, other codec controls and actual audio/DSP
execution remain absent.

One request owns reply metadata. Duplicates/NACKs replay its cached result with
the same device sequence, without rerunning codec reset. Positive ACK advances
the sequence. Output backpressure holds the byte and checksum state. Native D0/01
can re-request link reset; disable/reset cancels partial state. Timed retry, long
or fragmented application operations and other DSP services are unsupported.
ADSP_EXTERNAL selects an external transport only in existing UART fixtures;
production uses the integrated peer and there is no OSD/config enable option.

Validation:

* adsp_boot_peer at78/104MHz schedules: startup confirmation, CRC/routing,
  codec stalls, all prerequisites separately, unknown test/operation, duplicate/
  NACK replay, sequence, disable/reset; no second codec reset on replay.
* native_adsp_boot: original CBUS503822BC/table, UART RX-start510E876C,
  TX-start510E88C8, drain510E89CC, ISR510E8D58 and real HAL/IAT instructions run
  on HDL CPU through production board/UEM/UPP/EUART/FIQ26/D550/N501. Authoring
  supplies the caller, object/cache backing and FIQ wrapper, not guest code
  substitutions or a fake receive handler. Waits0/3 and78/104MHz schedules pass.
* test_native_adsp_boot_protocol.py executes original NOS request creation,
  original ARM normal-fragment builder, validates the actual CPU-captured ACK
  against its outstanding original packet, then runs the actual8B through the
  original checksum/frame-to-Phonet code and unchanged NOS result/free path.
  The original3000 timeout is checked. Allocator/descriptor/timer/transport leaves
  are explicit; this is not a full RTOS boot or a physical deadline measurement.
* UART, shared SIM/UART CTSI, CBUS and132 retained board ownership checks pass.
  MiSTer internal-CPU integration and original drain positive/negative controls
  also pass. Native boot fixture takes97,708/129,410 clocks at waits0/3.
  Quartus source graph has176 required files/9 unique QIPs. Verilog2001 and pinned
  formatting checks pass. Native driver tests retain immutable original code.

The first native CPU fixture lacked its CBUS cache backing and wrote through a
null pointer. Explicit authored cache storage fixed the fixture, not production
HDL. The deliberate one-cycle admission register required the standalone start
fixture to allow that cycle; no hardware expectation was relaxed.

Run `sh tests/phone/native_adsp_boot/run.sh` on the host; it uses only the existing
offline simulator image. `sh tests/phone/adsp_boot_peer/run.sh` is the smaller
byte-level fixture. Build/run manifests and logs remain in build/sim/unit-native-
adsp-boot and unit-adsp-boot-peer; selected small evidence is recorded alongside
the earlier capture evidence. No new disk or ROM files are needed on MiSTer.

---

# Native D550 link startup — 2026-11-14

RF startup1E passes on installed646ac68/seed44. The next captured failure is
an ADSP response assertion, and the D550 byte receiver remains disconnected in
production. This change implements and tests the D550 startup transmitter;
it does **not** yet fix original-firmware boot or select a production DSP peer.

## Actual unexpected response captured

An observation-only NOS response/assertion probe records:

```
resource/message 59/02, source object0x39, destination0x23
000000590600233908020100ffffffff
St_product.c / DF2 / pResp_adsp->message_id == ST_ADSP_RUN_RESP
LR516A629B
results 03030000 00030000 03000000 030d0000 03030301 04030300
```

The original ADSP waiter516A6218 expects8B. Generic dispatch51591810 can place
this unrelated59/02 into the common response slot while that waiter is active.
The logged16-byte window includes four trailingFF bytes outside the declared
message length. RF1E remains00; ADSP36 is03/pending at the assertion. Object0x39 has not been
positively associated with a process in this boot. Historical BTTestServer
attribution is a lead, not current proof. Do not filter59/02, change the waiter,
extend deadlines or fabricate8B in NOS as a fix.

The first UART observer watched only BL510E8D0C: it logged no bytes before the
assertion. That alone did not establish silence on the whole UART. A second
observer intercepts shared HAL halfword-write50324608, preserves CPU state and
replays the original MOV/STRH. Its qualified130s/520-snapshot interval contains
UART initialization and one0000 write to150554, but no startup packet. It does
not reproduce the assertion in that interval, so absence-before-assertion must
not be claimed from this different run. The late60s attachment has a reader gap;
exclude it from absence/timing conclusions. These are instrumentation-dependent
observations, not a proved host-driver defect or a measured startup deadline.

Both installers retain the original checksum check and recompute its diagnostic
expected MD5. They reject warm/cached state and require full original ROM hash,
fresh physical Hold, saving Off, restored media and advancing snapshots. UART
HAL hook tests cover48 SVC/IRQ/FIQ/system cases, unrelated-register silence,
flags/SP/arguments/callee registers and exactly the original halfword write.
Response/assertion wrappers pass nine additional native-context fixtures.
Reload removed every hook. Original ROM88fd..., automatic Run/save-Off and
unchanged C4a75.../PMM71189... were verified; no card writes or backups.

## D550 initiates the startup exchange

Original E403A400H450.USB SHA0be93de0... contains these constructors:

* 448CDA emits D0/01, payload01/11/01/(sequence|60).
* 448C33 emits D0/04, payload04/01/(sequence|60), then alignment00.
* Loaded RAM03FCA4 initializes sequenceD8E7=0, calls448CDA with0, then448C33
with the sequence. File offsets1741A/17425 are in load record16: they relocate
to03FCCA/03FCD5, **not**41741A/417425 executable flash addresses.
* RAM03FB53 also calls448C33 with0 in its D0/01 receive path. Reset/retry and
normal data sequencing need further qualification before a complete peer.

The wire packets, including55/55 synchronization and XOR16 checksum, are:

```
D550 -> ARM: 5555200078d000040111016058a5
D550 -> ARM: 5555200078d00003040160003cd2
ARM  -> D550:5555207800d000030501400065aa
```

The synchronization word is excluded from checksum. The second length is3;
its extra00 aligns the checksum. Flags60/40 and capability11 are retained from
the original code; no invented meaning is assigned to undocumented bits.

`tests/tools/test_native_adsp_bootstrap.py` executes original ARM checksum,
D0 resource/subtype dispatch510ECBA6..510ECC8C, constructor510EDEA8 and flag/
sequence helpers. D0/01 alone leaves the fresh host unready. D0/04 emits exactly
D0/05, sets host+14=1, resets the transmit sequence, handles host+94 pending
state and repeats correctly on another D0/04. Every single-byte corruption of
all three frames is rejected by the unchanged checksum verifier. Full ROM
immutability is checked. Descriptor, allocation, delay and send callbacks are
explicit fixture leaves; no kernel scheduler, full RX parser or UART integration
is inferred. An early fixture incorrectly made TPtrC8 twelve bytes, overwriting
its caller's stack slot; the corrected eight-byte leaf passes. That failure was
not a firmware or hardware bug.

## Implemented boundary and next integration gate

`rtl/ngage_adsp_bootstrap_tx.v` sends the two original sequence-zero packets
under a bounded request/byte/completion handshake. A stalled byte stays owned;
completion means delivery, never link-ready or diagnostic success. Reset
cancels partial output, and a new request restarts at the first sync byte.
Seven source state bits, no array, new BRAM, DSP interpreter or clock counter.
Tests pass at78/104MHz schedules. Actual fit/STA is NOT_RUN; production PLL78MHz
and104MHz objective are unchanged.

This submodule is not selected in files.qip or wired to MiSTer yet. There is
no new OSD option. Production still drains host TX and has no D550 RX. Before
selecting a complete peer:

1. Establish actual D550 reset/clock release and UART receive admission from
   the original ADSPCTRL/UEM operations; do not transmit at arbitrary CPU boot.
2. Consume/validate the original ARM D0/05 and qualify subsequent request,
   sequence/ACK/reset/retry behavior against both original firmware sides.
3. Connect the existing test42 operation and N501 codec model using qualified
   clock and D551 marker ownership, then form the actual8B diagnostic response.
4. Exercise the original host driver/CPU through board UART/FIQ with backpressure,
   malformed traffic, resets and failed prerequisites, keeping original deadlines.
5. Build only that integrated correction, then require native ADSP36=00 on board.
   SIM serving readiness remains a separate unresolved gate afterward.

Commands, using the existing offline simulator image and Linux Unicorn:

```
sh tests/phone/adsp_bootstrap/run.sh
python3 tests/tools/test_native_adsp_bootstrap.py
```

Private bounded sources, manifests and raw captures remain in
scratch/adsp-native-20261114 and scratch/adsp-hal-20261114. Compact capture
identity/qualification is retained in evidence/adsp-native-link-2026-11-14.json.
