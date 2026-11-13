# Native RF completion lost at the UPP DSP media filter

On installed91045a6, the native RF request reaches MDI and is consumed, but the
UPP DSP peer rejects its media byte12. The previous peer accepted only00.
Allow12 alongside the existing00 profile, preserving F1/A0, length, destination,
subtype and explicit revision03 checks. No state, RAM, queue or clock is added.
This is a verified source fix; the installed FPGA still contains the defect.

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

Next gate: build/deploy this actual HDL change, then qualify the original RF
startup result on hardware with unchanged firmware/deadlines. SIM readiness and
external D550 ADSP remain independent unfinished work. No installed RF fix or
timing closure is claimed yet.
