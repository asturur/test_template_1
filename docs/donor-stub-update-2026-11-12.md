# Updated donor NOS/SIM/BT comparison — 2026-11-12

Read-only comparison of donor `0fe531fd1c0a48a0d94d82d24371d848c9e7da2b`.
No donor, production HDL, firmware, media or board changes. Our strict original-
firmware/HDL-only boot is still incomplete. No new fit or timing measurement.

## Retail input does not mean unmodified execution

The donor now takes RH-29 retail4.10 service containers, replacing its previous
operator4.60 pair. `firmware-patches/rom-patches.txt` explicitly replaces NOS
entry CS0:9E4C4 and hidden NOS DLL CS0:A1C90, changes two hci.dll retry limits
at46DC52/46DDAC, and regenerates integrity entry8F18. The FPGA loader
`rtl/mister/phoenix_load.sv` executes PFETCH/PBYTE and writes these patch bytes
into the loaded image. Original files stay unchanged on disk; executed firmware
is patched. This does not satisfy our requirement and is not a new hardware
NOS/Bluetooth implementation. QD patch addresses must not be applied to NEM-4.

## Useful findings and disposition

| Contract | Donor observation | Our coverage / HDL-only disposition |
| --- | --- | --- |
| INFO IMEI | Commit05fe43d answers resource1B/message00/target41 with response01, status00, one subblock `41 14 00 10`, fifteen ASCII zeros and NUL. SPMark04 otherwise waits synchronously on a blank view. | Native NEM-4 response already recovered in modem-model.md section3.5 and matches this shape. Trace native serial reader514BF528 through its permanent-data backing; supply valid identity at the modeled device/data boundary. Do not add a second ISI server or force guest reply. Not demonstrated as our boot blocker. |
| SIM dynamic flags | Commit4f4eb29 adds09/29/service37 ->2A/37/24. Unsupported optional data still completes Settings; no reply left an empty view. | Our experimental virtual_sim.c has no explicit29 branch and defaults toFA. It is not production HDL and its fallback has not been shown to hang this client. Add native NEM-4 producer/consumer coverage; trace the actual SIM operation before selecting an EF or device response. No claim that native NOS lacks this handler. |
| SIM readiness | Initial1C/10 reply followed by09/EF `0D 0B 08 00`; DOS event17 makes System Agent100052E9=7. Security08/10 `05 00 00 00` makes100052F0=0. | Confirms the logical state needed by Startup, consistent with our prior experiment. Must arise from original NOS initialization, SIMIF/card and MTC/security producers. Direct RAM state writes or synthetic broadcasts remain disallowed. Donor skips these physical dependencies. |
| Phone/Menu waits | Ciphering09/60 ->61/FA31; provider21 ->22/2C24; operator33 ->34/3E24; service table13 ->14/1124; ALS/CSP31 ->32/3B24. | Already represented in our software experiment. Use as client completion/negative-response fixtures while exercising original NOS. A generic unknown/error code is not necessarily a valid completion for every client. |
| Bluetooth | No BT UART controller answers. hci.dll retry comparisons9 ->0 release the channel earlier, avoiding contention between BTTestServer and emon. | No new controller solution. Native LRB2 reset/start/query and UART/IRQ ownership still need implementation and tests. Do not port retry patch. Faster CPU can expose the contention earlier; speed alone is not a fix. |
| Self-test | Resource35 and59 replies directly report pass, reaching DOS event1=3. | Not evidence for native RF or D550 diagnostic behavior. Keep our internal-DSP version fix and external ADSP test42 investigation; do not copy unconditional pass. |
| ARM game audio | Resource1F/04 release ->06/0D00 lets SoundDevice leave teardown and accept a second stream. | Useful future start/stop/restart regression. Donor PCM path uses a declared HLE device and NOS replacement; it is not a native DSP implementation. |

Donor profile is **ready inactive SIM, no PIN/security query, modem normal,
no network**. It does not provide a registered fake carrier. Stale comments in
nos_isi.c/header say no SIM; actual state8 and NOS_STANDIN.md are decisive.
The donor documents Device > Display still waiting on resource3A; it is not a
complete peripheral specification.

## Focused validation and limits

Compiled the actual donor nos_isi_replies.h against a host queue capture in
`scratch/donor-stub-update-20261112/probe.c`. Six checks pass: exact IMEI/body/
header routing, unsupported IMEI target produces no reply, dynamic-flags error
completion bytes, ordered SIM/security indications, ciphering reply, and
unconditional self-test success. Results in the adjacent results.txt; source
identities in evidence/donor-stub-update-2026-11-12.json.

These execute the software stub only. They do not verify NEM-4 consumers,
physical SIM EF selection, native NOS readiness, permanent-memory identity,
Bluetooth hardware or complete boot. Existing NEM-4 IMEI evidence was reused,
not newly executed. Host PhoNet length4/5 is little endian; native MDI wire
transport has different framing and must not inherit that layout blindly.

## Implementation and acceptance order

1. Finish native startup hardware already under investigation: distinct D550
   ADSP transport/codec diagnostic and SIM/MTC readiness. Require unchanged
   native drivers, reset/absent/present, stalled delivery, ACK/IRQ ownership,
   failure propagation and normal firmware deadlines; never force ready/pass.
2. Trace NEM-4 IMEI reader514BF528, formatter514BFC7C and validator5164C274 to
   actual permanent-data ownership. Test valid/missing/malformed identity,
   correct15-digit formatting, request completion and PMM save/reload. Do not
   confuse the identity record with the separate unresolved50/1 default.
3. Trace native SIM29/37 request and its card/backend getter. Test supported
   data and legitimate missing-file completion, repeated/canceled transactions,
   ownership, and Settings opening. Determine actual EF from code, not QD guess.
4. Implement native BT response behavior at LRB2 boundary. Test HCI reset/start/
   query, simultaneous startup clients, timeout/reset/retry and UART FIFO/IRQ
   ownership; ensure channel release without firmware retry edits.
5. Cold boot audited unchanged firmware/C/PMM profile with original deadlines,
   verify Phone/Menu, Settings and an identity-reading application, then restart
   and persistence. SIM-ready does not prove network registration. Keep78MHz
   PLL, design104MHz and BRAM-backed bounded storage; no additional duplicate
   NOS message queues or diagnostic renderer.
