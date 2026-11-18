# Native RF startup observation and reproducer

See `docs/rf-native-media.md` and its evidence JSON first. This is diagnostic
software, not production firmware. The production fix is the media12 acceptance
in `rtl/ngage_upp_dsp_peer.v`.

`sh scratch/rf-timeout-20261113/run.sh` builds eight register/flags/SP/return
fixtures at memory waits0/3 in the cached simulator image. It also prepares a
board installer; it never connects or installs. Run from the repository root.
The fixture's native tail functions are assertions, not device success stubs.
`build_probe.py` reuses the maintained MTC fixture sources and existing qualified
exit/SIM/DOS observer artifacts. Rebuild those artifacts with their existing
tools if missing. All generated binaries, captures and installers stay ignored.

The RF veneers occupy original zero padding `51716A00..51716FFF`, following
the original NOS body ending51716900 in its already mapped last ROM page.
Backing offset is316A00, not1716A00. The installer checks every original zero
word. Its Thumb call sites have signed4MiB bounds and branch round-trip guards.
MTC's position-independent existing observer is relocated to511BE000; native
function, arguments and result bytes remain authoritative. The native startup
test registry is unchanged. The eighth veneer is an unused callback ABI fixture.

Log tags: R4 native startup send; R5 INFO manager; R6 builder; R7 routing;
R1 RF device send; R2 native MDI writer; R3 native RF receiver. Each logs original
r0..r3/LR, bounded packet bytes where applicable, both ring pointer words,
control and native pending state. Only ABI-scratch IP changes on the tailcall.
The INFO/RF hooks run in native NOS context, never an arbitrary DOS user wrapper.

Use the mister-control helper and guarded saved-Hold procedure. Require fresh
physical Hold, save Off, original full ROM and successful apply/full readback;
restore saved Run before starting. Reload removes every hook. The final board
state is original ROM88fd..., automatic Run/save-Off, unchanged C4a75.../PMM7118....

Authoritative capture: `mapped.jsonl`, decoded `mapped-text.txt`,
`applied-mapped.json`, `restored-identity.json`; 380 snapshots/no gaps/panic/fault.
Exact native RF packet: `127c00f10006012420a00255`. Padding55 is uninitialized
allocation data, not a required zero. Native RF fails01 in this diagnostic boot;
the earlier qualified handoff boot failed0D. Both lack device completion; do not
equate their upper-layer failure paths. No R3 callback; D2M stays00040004.

Rejected diagnostics worth preserving:

- `running`, `expanded`, `expanded-later`, `client`: initial unchecked Thumb BL
  targets511BDxxx exceeded range at the RF sites and wrapped to519BDxxx. Mock
  veneer ABI tests alone did not test call-site reachability. Native panic was
  visible even though reset/first-bus-fault stayed0. No absence/timing conclusions
  may use those captures.
- `corrected`:513BD000 was in branch range but outside native mapped ROM. Native
  panic at513BD00C invalidates this capture. The final NOS-page placement fixes
  both problems. A zero-padding original-word guard also refused an incorrect
  FF expectation before any board installation.
- Host Unicorn SIGILL: use the already retained Linux wheel at
  `scratch/profile-records-20261113/linux-unicorn/site` inside the offline image.

Focused Verilator negative: `native-before/captured-run.log` uses unchanged
parent peer RTL and the exact captured packet with original native ring code;
it times out. Positive: `native-mdi-captured.log`, waits0/3=4913/7367 clocks.
The maintained peer/ring tests also exercise native media12 and legacy media00,
alternate object routing, unsupported media/resource/subtype/length, reset,
backpressure, publication and IRQs. No new RBF, CI or long simulation was run.
