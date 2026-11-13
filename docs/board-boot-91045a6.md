# Board boot91045a6 — 2026-11-13

## Build and deployment

Completed Actions run43481493258 produced commit91045a6, seed44. Its final
status is failure because the required timing gate fails, not because the RBF
is missing. Worst reported setup is -0.198ns; the console core-clock row is
-0.056ns. Timing is not closed. Actual PLL stays78MHz, target104MHz.

Deployed4505528-byte RBF with SHA256
`c14825461fb74e01d39eeb7436b2233856d9a29644eaca1ed5b5bbbb61e56f28`
to /media/fat/_Console/ngage1.rbf. Staged, fsynced and hash-checked before atomic
replacement, then read back; no SD backup. Full firmware backing88fd596a...
verified after reload. Approved six-profile C4a75e4cb... and PMM71189f7f...
are unchanged. The latter hash is exactly65536 erased FF bytes; missing factory
PMM data alone is not proof of a failed flash operation.

## Clean original-firmware result

160s/640 snapshots, no reader gaps, reset generation0, first-fault reason0,
healthy save queue, save Off. Phone reaches Insert SIM. Menu one-second hold
arrives as key40 but leaves the screen unchanged; digit1 displays1. No boot
completion or Menu success is claimed. Captured LCD column pairs now appear
correct; physical CRT was not independently qualified.

The native flash-command fixes remain independently demonstrated by before/
after tests of unchanged Intel and AMD drivers. This board comparison does
not establish that they removed the Menu blocker or changed PMM provisioning.

## Correction to the active blocker map

Observation-only exit/descriptor plus PMM lookup traces do not reproduce
DSY USER21 or Phone/ViewSrv11 on the installed six-profile C. Earlier same-C
controls also lack those panics. The old missing50/1/DSY sequence belongs to
an earlier first-boot data path and must not be presented as the current crash.

Stable live PMM SHA0c24ff72... contains69 physical records, no group50/record1.
At native read5152BA5C's call5152BB02, observe original lookup515C705C results
without replacing them. Record1 reads include missing state0/null/busy0 and
present state1/nonzero results; group index7/record1 was not observed. Do not
infer the exact old50/1 error branch from this trace. Two equal DDR reads
capture committed PMM backing; they are not a firmware-cache or persistence proof.

## Native SIM and modem observations

Production Template still selects TEST_SIM_ENABLE=0 and sim_present=0; its QIP
omits the old synthetic card. This build therefore cannot initialize a serving
physical-card model. Native fallback observation actually sees SIM state5:
`Y SIM N 052f1901`, request message19/service2F. This is observed non-serving
state, not an invented reply or a proved independent SIM transport defect.

A scoped MTC observer tailcalls original5159A198 with original arguments,
flags, stack and caller.24 exact Thumb BL sites in the MTC region are redirected;
only r12/IP is ABI scratch. Actual ZAP tests at memory waits0/3 verify output,
arguments, callee registers, flags, stack and native ARM/Thumb return. The first
fixture had an outdated mock-function address and timed out; correcting that
fixture was required before any hardware installation. No firmware function,
message, status, deadline, storage data or test result is substituted.

150s/600 snapshots/no reader gaps show:

| Native call/result context | Observed values |
| --- | --- |
| Initial MTC indication | messageC0/action0C, native state3, SIM1 |
| Later request | message01/argument08, SIM5 |
| Later MTC READY | messageC0/action04, native state8, SIM5 |
| Subsequent response | message64/argument06, native state8, SIM5 |

Therefore READY is not completely absent in this cardless boot. It occurs for
state8; historical card-present queue-drain requirements were states1/4. These
are different inputs and must not be conflated. State3 provenance was already
traced in November5 simulations through RTC/startup selection; changing only
powerup-status1 to2 did not eliminate state3. Do not repeat that as a new fix,
force native NORMAL, or remove the RTC status bit without qualifying its client.

## Diagnostic scope and retained evidence

All observers require a fresh physical Hold, saved Run off, completed media
restore, original full-ROM/per-word checks and two advancing snapshots. The
checksum range/check remains; only the diagnostic expected digest is recomputed.
A premature installation attempt safely refused a still-loading ROM and made
no writes. Later preflight confirmed the full original hash and fresh Hold.
Automatic Run/save-Off settings are restored before starting each held boot.
Reload removes all observer hooks. Production acceptance remains entirely
original executable firmware with no observer writes.

Receipts, scripts, small probe sources and bounded captures:
`scratch/board-debug-91045a6-20261113/`, with summaries in capture-summary.json.
No other thread's simulations/checkpoints, SD data, PLL or production RTL changed
in this investigation. A subsequent DOS/native-NOS capture positively observes event1/value2 and
reads24 result bytes in the owning CPU context, not host SDRAM.560 snapshots,
no reader gaps/reset/first fault. Native bytes:
`03030000 00030000 03000000 030d0000 03030301 0401030d`.

| Test | Native ID | Result | Registry severity |
| --- | --- | --- | --- |
| Bluetooth LPRF interface |15|0D|0A|
| Current consumption |02|01|0A|
| RF chip ID |1E|0D|0C (fatal)|
| External ADSP |36|01|0C (fatal)|

Thus native startup reports failure in this cardless boot independently of
SIM readiness. RF0D matches the original client's timeout branch. ADSP1 alone
does not distinguish its timeout from a nonzero device result. Earlier MDI unit
fixtures do not establish that the full-board RF request actually reaches the
peer or its response returns before the original deadline. Next precise RF
boundary: native builder5164B3A4 sends at5164B4EE; receiver515920D0 fills the
RF cache; verify actual request/ring/IRQ/response delivery, rather than changing
the revision, timeout or test severity. Native platform selection reads the
modeled GSM strap; existing receiver fixture supplies platform-type1 explicitly.

An intermediate result-dump experiment in the DOS user context attempted direct
kernel-address/MMIO access and did not emit its dump. Its wrapper-only Unicorn
fixture did not model address permissions. That experiment was removed by
reload and discarded; no boot or test conclusion uses it. The maintained DOS
observer is unchanged. Corrected result reads run inside the native NOS MTC
observer; actual ZAP wait0/3 tests exercise all24 result bytes, native argument/
flags/stack/return preservation. Its first extended fixture omitted the result
RAM address window and failed output comparison; fixed before board apply.

Evidence: [board-boot-91045a6-2026-11-13.json](evidence/board-boot-91045a6-2026-11-13.json).
Final reload removed all observers; full original ROM88fd... and unchanged C/PMM
hashes are verified. Saved automatic Run/save-Off is restored. Final58 snapshots
have reset0/firstfault0/no queue fault; initial unread-backlog reader gap excludes
that short capture from timing/absence-of-events claims.


## Subsequent RF boundary capture (2026-11-13)

A qualified380-snapshot/no-gap/reset/panic/first-fault capture now observes the
complete native RF send through INFO, platform routing and MDI. Exact packet
127c00f10006012420a00255 is consumed; D2M stays4 and no RF receiver runs. The
installed peer rejects media12, accepting only00. An exact-packet Verilator
reproducer fails on this peer and passes with the source media guard correction.
Native RF result is01 in this observed boot rather than the earlier0D; no
functional result or original deadline was changed. Source repair is not yet in
this installed RBF. See [rf-native-media.md](rf-native-media.md) for the native
chain, local verification and rejected diagnostic attempts. Cleanup verifies
original88fd.../automatic Run/save-Off and unchanged C/PMM; no rebuild or CI watch.
