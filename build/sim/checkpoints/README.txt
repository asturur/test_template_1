Checkpoints (2026-10-29): correct UEM-path pinned snapshots only.
  mount-c760  - cycle 760M, pre-C:-mount window
  mount-c768  - cycle 768M, after F32 exercises C:, just before the re-idle
The pre-UEM c1300/c1307900000 snapshots were retired: they were captured
before uem-irq-source1 existed, so they followed the SHORTER epbus path that
never completed the first power instance (diverges from the current model by
~764.6M). Resume with run-resume-760.py / run-resume.py (auto-latest).
