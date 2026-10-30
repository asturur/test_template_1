Simulator snapshots (VerilatedSave .cpu + board .host).
A snapshot binds to the EXACT Verilated model that wrote it: after any RTL
change + rebuild, old snapshots are unusable and must be regenerated from
reset (scratch/boot-v15-nosprobe/run-fresh.py [budget] [name] [win] [ckpt_at]
writes fresh-c<N>). Resume with run-resume-from.py [budget] [name] [win]
[ckpt_at] [snapshot-name]. 2026-10-30: pre-CTR-fix snapshots (mount-c760/768,
idle-c1130) deleted - they bound to the pre-patch-0009 model.
