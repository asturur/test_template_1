# Native RF completion lost at the UPP DSP media filter

The media12 fix is now verified on the user's installed646ac68 RBF. Native
F1/A1 reaches the original receiver, and original startup test1E reports00.
This qualifies the RF success path; it does not establish repeated-boot reliability
or complete SIM/ADSP/Phone boot.

## Hardware qualification — 2026-11-13

Installed bitstream matches completed Actions43514093456 exactly: commit
646ac6848a73da72957c1a5c552eaf9b2612af8c, seed44,4495992bytes, SHA256
2399bb9e39dcc11db4c7be50bc6b688ea319f7a4668b44db4bd5a29114dc09fb.
No build/deploy or production RTL edit was needed in this verification session.
No FPGA timing-closure claim follows from it; operating PLL remains78MHz.

The existing qualified RF observer sees the same native request, now followed
by receiver515920D0 with keyF1A1/body20A10103. D2M pointers advance4->A and are
consumed. Native request-send to receiver-entry takes171225 clocks, about2.195ms
at78MHz including observation overhead. This is response-delivery latency, not
an independently measured full startup-function duration. Original timeout
argument500, revision03, result decisions and registry remain authoritative.

At the subsequent native NOS result dump, the original24byte array is
000003030000030000000003000001030103030300030104.
Registry-index20/ID1E is00; ADSP36 remains01. BT15/current02 are01. DOS event1
is still2 because other native startup work fails. SIM remains non-serving5;
screen shows Insert SIM. This is the requested positive RF board result, not
serving SIM, registered network or Menu success.

The qualified capture has460 snapshots/115s, no reader gaps, producer drops,
reset, panic, first fault or save-queue fault. Hooks are observation-only and
firmware checksum checking remains enabled. Source firmware is unchanged.

The first traced boot and a subsequent original-ROM/no-observer control
panicked after RF delivery, with recorder category prefixFILE: FI and reason
00010001. The clean control has560 snapshots/no reader gaps. The prefix alone
did not identify the source, so the native assertion was observed directly.

A minimal97-word assertion-only installer omits every RF/exit/SIM/DOS hook and
preserves the original assertion. It captures filename
../../ENOS/CMT_SW/CONFIG/St_product.c, line0xDF2, callerLR516A629B, expression
pResp_adsp->message_id == ST_ADSP_RUN_RESP. This is the native ADSP startup test
expecting its response, not a newly guessed RF receive-IRQ fault. Its CPU-visible
result array at that point is00000303000003000000000300000D030103030300030304:
RF1E is already00; ADSP36 is still03 (pending/unfinished). Current data does not
record the unexpected message's actual ID. The older November5 experiment
found unrelated5902 delivery here; that is a lead, not proof of today's byte.

This identifies the next observed blocker as the known unfinished native ADSP
response path. It does not qualify a serving SIM, external DSP or reliable Phone
boot. The successful115s RF capture had no panic; the ADSP assertion is therefore
an intermittent outcome of the remaining startup path, not grounds to discard
the positively observed RF result.

Assertion observer tests cover original args/registers/flags/SP/ARM tailcall,
bounded ROM strings, invalid pointers, immutable result reads and stack/debug-only
writes. The fixture initially set SP before switching banked mode; corrected
before installation. No production RTL, clock, timing constraint or card data
changed. The minimal capture retained475 snapshots/no reader gaps, then its SSH
connection timed out; a fresh authorized connection was established for cleanup.
Missing tail data is not used for timing/absence claims.

Normal reload removes all hooks; final original-ROM/card/settings verification
is recorded in the evidence. Source firmware stays original, Run/save-Off is
restored, and other-thread simulations and formatter setup files are untouched.

[evidence/rf-board-qualification-2026-11-13.json](evidence/rf-board-qualification-2026-11-13.json)
pins both captures, observed native boundaries and guard/readback receipts.
Local raw logs, summary tool and assertion probe are under
scratch/rf-board-qualification-20261113/.

## Historical91045a6 defect and source fix

On installed91045a6, the native RF request reaches MDI and is consumed, but the
UPP DSP peer rejects its media byte12. The previous peer accepted only00.
Allow12 alongside the existing00 profile, preserving F1/A0, length, destination,
subtype and explicit revision03 checks. No state, RAM, queue or clock is added.
This was the pre-build source checkpoint; the646ac68 board qualification above
now demonstrates the successful RF path.

## Qualified hardware observation

The existing DDR debugger and observation-only native NOS veneers captured
95seconds/380 snapshots, no reader gaps, reset, panic, first fault or queue
fault. Original executable behavior, checksum check, deadlines and registry
remain in control. The diagnostic checksum digest alone accounts for hooks.

| Native boundary | Observation |
| --- | --- |
| Startup send516A60FC | resource1B, body0C070020 |
| INFO manager5164AE78 | message1B07, same body |
| Builder5164B3A4 | flags20 |
| Routing5164B20C | inputA1; resulting device resourceF1 |
| Device send5164B4EE | body20A00255 |
| MDI writer514C4904 | complete frame127C00F10006012420A00255, six halfwords |
| Later ring ownership | M2D00100010, fully consumed; D2M still00040004 |
| RF receiver515920D0 | no callback |

The fourth payload byte55 is untouched allocation padding. Native code only
sets20/A0/02. It must not be validated as zero. Media12 comes from the native
transport; object routing is01/24. The expected modeled reply is
`12007cf10006240120a10103`, retaining media and swapping device/object endpoints.

The peer's media00-only condition rejects this exact otherwise supported frame.
Thus this loss occurs before response publication, rather than proving a
missing receive IRQ or a stalled request ring. Unknown F2/F3 traffic remains
unsupported; no additional native NOS responder or guessed replies are added.

Final native result bytes were
`00000303000003000000000300000d030103030301030104`.
RF registry1E/severity0C fails01 in this instrumented boot; the earlier qualified
handoff boot failed0D. Do not conflate an upper-layer rejected/error response
with the client's direct timeout branch. The demonstrated common defect is no
RF device completion. ADSP36 remains01, and native SIM remains non-serving5.
No complete Phone/Menu or serving-SIM success follows.

## Focused reproduction and validation

`tests/phone/native_mdi/program.S` now supplies the exact captured packet to
untouched native515BF550/515BF474/515BF65C/515BF7D8 on the actual HDL CPU and
MDI controller. Native ring receive checks all response bytes, including media
and endpoint routing. Caller/task setup remains a fixture, not the full NOS
scheduler, MMU or original RF client execution.

- Unchanged parent peer RTL with this same captured packet: Verilator times out
  polling native RX availability; no response is published.
- Fixed peer: native CPU test passes waits0/3 in4913/7367 clocks, the same counts
  as the former media00 fixture. No new ordinary-path clock or pipeline stage.
- Exact-packet peer Verilator and Verilog2001 peer/ring checks pass native12,
  retained00, alternate address/object routing, invalid media/resource/length/
  subtype, stalled responses, reset,250-halfword wrap, natural full-ring
  backpressure/release, publication and IRQ events.
- Existing board/CPU integration passes SIMIF, LCD DMA/queue, owned faults,
  diagnostics, IRQ/FIQ, SDRAM waits and live UPP shared-RAM DMA.
- Original client/receiver/builder/TX-task contracts pass using the retained
  Linux Unicorn wheel in the offline simulator. Revision03 passes,04 fails;
  original500 timeout remains. Those fixtures still do not prove full scheduling.
- Pinned RTL formatter and whitespace checks pass. Added storage is0 bits.
  No new fit/area/timing measurement;78MHz PLL and104MHz objective are unchanged.

Commands: `sh tests/phone/native_mdi/run.sh`,
`sh tests/phone/mister_board_cpu/run.sh`; peer/ring scripts run inside the existing
offline `jotego/simulator:arm64` image. Receipts are under
`scratch/rf-timeout-20261113/`; [evidence](evidence/rf-native-media-2026-11-13.json)
pins the captured bytes, source/build identities and scope.

## Diagnostic failures and cleanup

Initial RF veneers at511BD000 were outside signed4MiB Thumb BL range for the
RF sites. The encoder silently wrapped; direct mock-entry ABI tests missed it.
Native panic, rather than the first bus-fault field, exposed the mistake. A
second address513BD000 was reachable but unmapped. Both captures are rejected
for RF absence/timing conclusions. Final veneers use guarded zero padding after
the original NOS body in its mapped last page,51716A00; all branches are range
and round-trip checked. Eight ABI fixture entries pass at waits0/3. See the
retained experiment README before reusing this diagnostic.

Normal reload removed all hooks. Full original ROM88fd596a... and saved automatic
Run/save-Off are verified; C4a75e4cb... and PMM71189f7f... are unchanged. No disk
replacement/backup, RBF rebuild, CI monitoring, subagent or other-thread simulation
was used. A first cleanup hash read preceded completed restore and safely failed;
the later full verification passes.

The previously pending RF hardware gate now has a positive result above.
SIM readiness and external D550 ADSP remain unfinished; the native ADSP assertion above remains an active boot blocker. No full-phone boot or timing closure is claimed.
