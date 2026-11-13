# Fresh integration UI investigation

**Stopped at user request on 2026-11-12**, at10,107,094,767 cycles. Handled SIGTERM saved
a final CPU/host pair under `checkpoint-10107094767` in the run directory; container
exit confirmed. No automatic restart. Exact hashes and final result are recorded
in `scratch/sim-interactive-20261111/stopped-state.json`.

Launched 2026-11-11 as `build/sim/runs/integration-ui-fresh-12b`, target12B,
frozen model `8b92e8641d9c7365`. Initial container startup was confirmed. No
ongoing polling is permitted; inspect only on user command. HDL edits are safe
while this frozen executable runs. Its exact sources are in the run's
`compiled-sources.tar.gz`. No key request was made at startup.
[Control/restore verification](evidence/sim-ui-run-2026-11-11.json).

The integration core needs a cold-boot lineage; old-core checkpoints cannot
populate its changed register-file, cache, timer, ICU and DMA state. See
[checkpoint compatibility](checkpoint-compatibility.md).

The requested long run uses current HDL, production D1/D2/D3 DDR adapter,
78MHz CPU, 26MHz timer enable, NOS64, normal power-up, line refills and no
firmware overlays. The testbench preloads unmodified core/extension and a private
C: copy, initializes PMM erased and exposes no MMC card. Physical memory timing
and HPS persistence are outside this harness. The passive fault-context observer
records the Count-abort caller, registers and recent owned memory operations.
The run saves and exits on that abort, terminal kernel panic, interruption or
its final target, rather than wasting host time in the known panic sink.

## Checkpoint schedule

The host driver saves at 1B, 2B, ... 10B, then at 10.1B, 10.2B, ... . It also
saves at a terminal stop, even if that cycle falls between scheduled saves.
Every save is a paired `.cpu` and `.host`; partial writes are not resumable.
The schedule lives in the run manifest and can be overridden for bounded
control tests through `--checkpoint-before`, `--checkpoint-switch` and
`--checkpoint-after`. Billion-cycle history must remain permanently retained.
Checkpoint-triggered screenshot extraction is automatic, not an agent polling
loop. Native images go to `build/sim/screens/<run>-checkpoints/`.

## Keys without rebuilding

Each new run has `key-command.txt`. Send a request with:

```sh
python3 tools/send_sim_key.py build/sim/runs/integration-ui-fresh-12b ok
python3 tools/send_sim_key.py build/sim/runs/integration-ui-fresh-12b menu --milliseconds 250
python3 tools/send_sim_key.py build/sim/runs/integration-ui-fresh-12b left_soft,star
python3 tools/send_sim_key.py build/sim/runs/integration-ui-fresh-12b release
```

Names: up, down, left, right, ok, left_soft, right_soft, menu, clear, send,
end, power, music, radio, shift, star, hash and digits 0..9. A chord is a
comma-separated list. Default duration is 150ms of phone time, not wall time.
The simulation samples the command file every 65,536 CPU clocks. It sends
normal public key levels through the board keypad logic; it does not force a
keypad interrupt or UI response. GPIO configuration still governs delivery.

`KEY_REQUEST`, `KEY_APPLIED` and `KEY_RELEASED` record actual delivery/release
in `progress.log`, while `key-requests.jsonl` records user requests. Submit only
one outstanding request and wait for its application before replacing it;
the command file is a single slot, not a queue. No keys are requested by default.
The applied ID, held mask and remaining hold duration are serialized HDL state.
A checkpoint during a press resumes the hold and releases at the same guest
cycle. A fresh run's command file contains ID0, which cannot replay an already
acknowledged nonzero command. Resume from the matching frozen executable and
manifest, then send new requests using the new run directory.

## HDL edits and run lifetime

Once compilation and launch finish, the process uses its frozen executable.
Editing workspace HDL cannot change that process. Keep its cached executable,
compiled model archive, source manifest and checkpoint/input files intact.
A separate changed-HDL boot is needed to test fixes; `--use-saved-build` always
runs the old executable. Do not rebuild in place over the frozen model folder.
No agent polling is required; inspect progress only when requested by the user.
