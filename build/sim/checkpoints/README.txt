Simulator snapshots (VerilatedSave .cpu + board .host).
A snapshot binds to the EXACT Verilated model that wrote it: after any RTL
change + rebuild, old snapshots are unusable and must be regenerated from
reset. A board-model (boot_profile.cpp) change alone keeps the model and the
snapshot valid.

Resume: scratch/boot-v15-nosprobe/run-resume-from.py [budget] [name] [win]
[ckpt_at] [snapshot-name]. From reset: run-fresh.py [budget] [name] [win]
[ckpt_at] (full flag set incl. cdrive-image).

Current bases (post CTR-fix patch 0009 + C: byte-read fix, 2026-10-30):
  fresh-c1250  - cycle 1.25e9, EStart ready, StartupThread exited
  idle-c3500   - cycle 3.5e9, boot stalled on the NOS Variant iface-#13
                 waiter (ekern ord252 / global 0x800004ac); nearest base to
                 that frontier. See docs/status.md top entry.
