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
