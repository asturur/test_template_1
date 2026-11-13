# Next board debugger baseline — 2026-11-13

User will build the published integration branch and then run a DDR debugger
session. Do not launch or monitor CI, deploy/reload a core or operate the board
as part of publication. Keep78MHz PLL and104MHz design objective.

The active image includes native SIMIF W1C, idle CBUS completion, UPP internal
DSP-version transport and EUART/CTSI ownership fixes. It retains DDR diagnostics
and excludes the retired diagnostic renderer. External D550 peer and synthetic
SIM presence remain inactive. Standalone D550 test42/N501 modules are reference
implementation/tests, excluded from QIP. No startup ROM/RAM patcher is enabled.
This build is a diagnostic baseline, not a claim of unmodified Phone/Menu boot.

## One failure at a time

1. Pin RBF/source commit, MCU/PPM and C/PMM identities; use the known-good disk
   pair and Background save Off. Start a read-only DDR capture before CPU Run.
   Preserve exact native text, snapshots, reset generation, fault/panic fields,
   bus/fetch history, timestamps and drop/overrun counts.
2. Find the first reproduced failure in THIS image. Historical first confirmed
   fatal observation was Phone's ViewSrv11; earlier Bluetooth errors were not
   sufficient to explain it. Do not assume the new build reaches the same stop
   or that ADSP is necessarily its first cause.
3. State the observed request/response or fault and its owning component.
   Separate evidence from hypotheses. DDR contains text/monitor/history, not an
   arbitrary external-SDRAM/process-memory debugger; if insufficient, identify
   one narrow missing observation before changing behavior.
4. Implement one evidence-backed HDL correction with a focused native-driver
   regression, preserving original executable firmware/deadlines. Compare the
   same boot/media/input and only then select the next failure.

Do not apply BT/NOS/SIM software overlays, tracer instruction hooks, ready-state
writes, self-test exclusions, PMM record injections or timeout extensions.
Retained overlay/tracer tools document past experiments; their presence in the
repository is not authorization to execute them in this session. Read-only SSH
capture is tools/ngage_runtime_diag.py; credentials are never committed.
