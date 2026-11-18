Continue N-Gage ngage1 bring-up. Your immediate task is to reproduce and fix the native RF chip-ID startup timeout in HDL, one issue at a time. This is an implementation/debugging task: investigate autonomously, reproduce the actual failure, fix its owner, and verify it. Do not stop at a plan or ask routine permission. Do not claim complete Phone/Menu boot from fixing this one test.

WORKSPACE AND SOURCE STATE
- Actual repository: /Users/andreabogazzi/develop/NGage_MiSTer
- Branch: codex/ngage2-integration
- HEAD: edc4c2f (test(boot): pin native startup blockers). This commit is LOCAL, not pushed; it contains tests, observer source and documentation, no production HDL change.
- Parent91045a6 is the currently installed FPGA build and contains the native PMM flash-command repair.
- Worktree was clean after edc4c2f. Check current status before editing; preserve any changes from another chat. Do not use the obsolete integration-worktree path as the working checkout, switch branches, create another worktree, or touch the other thread's simulations/checkpoints.
- Read AGENTS.md, then the NEWEST entries at docs/status.md, followed by docs/README.md. Older status handoffs are historical, not current instructions. Keep relevant topic docs, status and merge-plan.md current.

REQUIREMENT AND SCOPE
The final core must boot strictly unmodified executable firmware through device behavior in HDL, with original NOS running. No functional ROM/RAM patches, synthetic NOS-ready broadcasts, fabricated test passes, test-registry exclusions, timeout extensions, or automatic startup patch loader. Explicit synthetic hardware identity/card data at the actual device boundary is allowed, with protocol limitations documented. Never add a second NOS responder to bypass the original NOS.

Observation-only, volatile software instrumentation through the existing DDR debugger is authorized, if properly qualified and guarded. It must not change firmware decisions/results, and must be removed by reload afterward. Keep disk data unchanged, Background save Off, and do not select Flush. The user explicitly does not want SD backups of reproducible files.

Keep operating PLL at78MHz. Design toward104MHz, watch ALM/MLAB/BRAM use, avoid extra queues and diagnostic renderer logic. New maintained HDL must be Verilog2001 compatible. No subagents, no CI/build monitoring, no Quartus download. Use the existing jotego/simulator:arm64 Docker image and small focused reproductions; never restart an hours-long whole-phone simulation just to rediscover documented behavior.

READ THESE CURRENT ARTIFACTS
1. docs/board-boot-91045a6.md and docs/evidence/board-boot-91045a6-2026-11-13.json: deployed build identity, positive hardware findings, corrections and diagnostic limits.
2. docs/native-startup-hdl.md, especially "Native RF provider and UPP internal DSP link": recovered native chain, model/tests and explicit qualification gaps.
3. docs/sim-adsp-native-progress.md: latest donor-author checklist and native handler tests.
4. docs/menu-blocker-map.md: historical and current blockers are now explicitly distinguished.
5. docs/bringup.md and relevant RTL-style/chip-inventory docs before choosing tests or changing boundaries.

CONFIRMED CURRENT HARDWARE FAILURE
The latest qualified observation-only capture on91045a6 has560 snapshots, no reader gaps, reset generation0 and first-fault reason0. DOS publishes event1/value2: native startup failure. A CPU-visible read in native NOS context captures the original24byte result array at80024388:
03030000 00030000 03000000 030d0000 03030301 0401030d

Decoded against the original registry:
- RF chip-ID test1E =0D, severity0C (fatal). This value matches the original RF client's timeout path.
- External ADSP test36 =01, severity0C (fatal). Result1 alone does not distinguish timeout from a nonzero device result.
- Bluetooth/LPRF test15 =0D and current-consumption test02 =01, severity0A (lower severity).

Focus on RF first: we already implemented a version responder, yet the integrated board still times out. Do not say RF is fixed from isolated passing tests, or assume those tests cover the missing full-board path. Next identify whether the real request is constructed/sent, reaches the ring/peer, gets a response, and is delivered to its original consumer before the native deadline.

EXACT RF CHAIN AND RELEVANT SOURCE
- Unchanged startup function516A60C0 sends resource1B, body0C070020. Native timeout argument500; first invocation returns pending2; timeout writes0D. Do not alter either.
- Info_SrvMgr5164AE78 handles1B/07 flag20.
- Builder5164B3A4 constructs the RF-version request. The RF send call is5164B4EE ->514BA3F0. Capture real arguments/body here as a candidate first probe rather than inventing a packet.
- Native routing helper5164B20C uses platform-type getter514C1604. Selected platform1 routes to resourceF1. The getter reads the GSM strap at virtual58150002; production ngage_upp_peripherals.v supplies physical0C150000 bit22. Existing receiver fixture STUBS platform-type to1, so its pass is not full-board proof.
- Expected device transaction from recovered code: F1/A0 body20A00200; response F1/A1 body20A10103 for the explicitly modeled revision03.
- Receiver515920D0 converts the device revision to decimal string03 in native RF cache80009D3C. Native INFO builder5164C3EC creates subblock54. The original startup function accepts03 and rejects04.
- Production RTL: rtl/ngage_upp_mdi.v and rtl/ngage_upp_dsp_peer.v; wiring in rtl/ngage_board.v, routing in rtl/ngage_upp_peripherals.v.
- UPP MDI is distinct from external D550 audio DSP. M2D ring0C100000..0C1001F3, D2M0C1001F4..0C1003E7,250 halfwords each. Pointer words0C1003E8/3EC: producer low16, consumer high16. Control0C14B004 low0500 enables link. IRQ9 signals M2D consumption, IRQ10 D2M publication. Native Phonet length is big endian; ring driver swaps halfwords. Validate actual ownership, framing, publication and IRQ acknowledgement.
- Existing tests: tests/tools/test_native_info_version.py, test_native_startup_contracts.py, test_native_mdi_contract.py; tests/phone/upp_dsp_peer/, upp_mdi/, native_mdi/. Read their scopes: the native ring CPU fixture uses an AUTHORED frame/caller, and receiver fixture supplies platform-type. Do not repeat all tests or infer end-to-end coverage from them.

HARDWARE ACCESS / SUGGESTED SKILLS
Use /Users/andreabogazzi/.codex/skills/mister-control/SKILL.md and its references/ngage-software-observer.md before hardware commands, input, screenshots or DDR captures. Announce skill use. Use its helper and cached APIs/key values; do not search other Zaparoo/MiSTer projects to rediscover commands.
- MiSTer endpoint192.168.1.176, SSH userroot. Password access was authorized earlier; reuse the existing SSH master scratch/ngage-diag.sock where available. Do not put credentials in notes or commits. If the connection needs reauthentication, use approved credentials securely.
- Core: /media/fat/_Console/ngage1.rbf. Data: /media/fat/games/ngage1/.
- Installed bitstream: commit91045a64fb035eaf16e84e3f9f0e03b7cd6bdadd, seed44,4505528bytes, SHA256c14825461fb74e01d39eeb7436b2233856d9a29644eaca1ed5b5bbbb61e56f28.
- Build run43481493258: https://github.com/asturur/test_template_1/actions/runs/43481493258 . Artifact was deployed and verified. The action failed its final timing gate; worst setup-0.198ns, console core row-0.056ns. Do not claim timing closure or dismiss timing as impossible to contribute.
- No new RBF is needed for the next observation. edc4c2f does not change production HDL. Do not launch an unchanged rebuild.
- At handoff, every observer was removed by normal reload; complete original firmware backing SHA25688fd596a23269ecb0d9f7544d540c59010d276574dbe3d0262c870c429e58329 verified. Saved automatic Run is restored, save Off. Do not assume current warm-running code can safely be hooked.
- Both card images verified unchanged: C boot0.vhd4a75e4cb75d5fb25c4148f888e3e4858e37841f97834df7a002d6f38ca15b329; PMM boot1.vhd71189f7fb6aed638640078fba3a35fda6c39c8962e74dcc75935aac948da9063. PMM is exactly64KiB FF on card, initialized by native NOS in volatile backing each boot.

DIAGNOSTIC SAFETY AND REUSE
Reusable qualified probe sources: scratch/board-debug-91045a6-20261113/mtc/README.md, trace.S, prepare.py, prepare_dos.py, run.sh and fixture sources. These are tracked in edc4c2f. Generated captures/manifests remain local. Full evidence is under scratch/board-debug-91045a6-20261113/; last qualified result capture mtc/nos-result-running.jsonl, decoded nos-result-text.txt.

Preparation must require fresh physical CPU Hold, saved Run off, complete media restore, save Off, zero execution/ACK/error history, original full-ROM and per-word checks, and two advancing snapshots. Qualify new hooks' actual ABI and state preservation before installation. Inspect successful apply/full-image readback before starting. Retain firmware checksum range/check; the observer generator recomputes only its diagnostic expected digest. Never use the old BT/SIM bundle as a base for observation.

IMPORTANT failed approach: a DOS user-context dump tried direct kernel-address/MMIO access. Its wrapper-only Unicorn fixture did not model permissions; hardware dump failed. It was discarded and removed by reload. DOS observer source is unchanged. Correct24byte result reads occur in native NOS MTC context, with actual ZAP wait0/3 tests. Respect address-space/cache ownership; host SDRAM reads may miss dirty CPU cache data. Never copy direct debug59 MMIO or NOS-global reads into an arbitrary user-thread wrapper.

For temporary saved Hold settings, use the exact guarded procedures in the skill and existing scratch/menu-native-retrace-20261113/ scripts. Saved Run/save-Off bytes were00000100000000000000000000000000. Verify current bytes before editing. Inspect CURRENT Template.sv CONF_STR before any OSD row-count macro; menu removals already invalidated earlier recipes. Do not press Enter on Flush. Restore saved Run and remove observers when done.

OTHER FINDINGS TO KEEP SEPARATE
- Clean original-ROM/six-profile-C boot reaches responsive Insert SIM and digits. Menu does nothing. No current USER21/ViewSrv11 reproduced on this C; old same-C controls also lacked them. Missing PMM50/1 is not the current proved crash.
- Six-profile C is an explicitly approved workaround. Native first-boot profile rebuild exceeds deadlines and remains unresolved; no VHD-conversion data loss proved. Do not replace disks or reopen that investigation during the RF fix.
- Production disables synthetic card/presence: TEST_SIM_ENABLE=0, sim_present=0, old card source excluded. Native SIM is observed non-serving5. MTC later publishes READY/action4 for MTC state8, so READY is not completely absent. Historical card-present experiments differ.
- Donor author's ready status7 (System Agent), native SIM_Server serving8, and MTC state8 are different fields. The donor replaces NOS; copying its ready/unsupported replies is not our HDL solution.
- New original-handler tests already pass optional21/2C,13/11,31/3B,33/3E,29/37 ->24; native cipher callback0/1/2 ->24/30/31. See tests/tools/test_native_sim_optional_queries.py and test_native_sim_ciphering.py. Transport/callback delivery are fixture leaves, so no native serving-SIM or real scheduler qualification is implied.
- INFO_PP_READ1B/02 is product-feature configuration, not Phone profiles or a SIM EF. Native dispatch/reader exist; valid factory provisioning/end-to-end hardware response are not qualified. Do not inject zero because the donor does.
- Flash91045a6 fixes genuine Intel erase/status and AMD erase/program-tail command defects with original-driver before/after tests. It was NOT shown to fix Menu or PMM50/1 provisioning. Preserve that qualified fix unless new evidence demonstrates a regression.

EXPECTED NEXT WORK / COMPLETION CRITERIA
1. Confirm current repo/hardware state, then make the smallest safe observation needed to locate the RF request/completion loss. Reuse current DDR diagnostics; do not add FPGA instrumentation without a demonstrated need.
2. Capture actual native bytes and routing, distinguish unsent request, framing rejection, stalled ring, missing interrupt, response rejection and late completion. Do not pick a cause solely from a pending IPC or speculative fetch PC.
3. Reproduce the observed failure in a focused actual-HDL/CPU fixture, show before/after, fix its proper chip/controller owner, and test success, invalid/unsupported input, reset/backpressure/publication/IRQ cases relevant to the defect. Keep fast ordinary paths fast and additions small.
4. Update evidence/status/merge-plan with measured results and explicit limits. A new FPGA build becomes worthwhile only after an actual HDL fix; use gh CLI for ALL GitHub actions, stop and repair gh if it fails. Do not monitor CI unless newly asked.
5. Qualify original RF test on hardware after deployment. Report separately that SIM readiness and external ADSP still remain. No full boot/menu success claim without actually observing it under original firmware/deadlines.

Communicate brief meaningful progress, avoid repeated permission requests, and preserve failed approaches so this chat does not repeat the old investigation spiral.
