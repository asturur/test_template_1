# Matched physical fit release

`prepare.py prepare` recreates both exact qualified source overlays from the
immutable ccba54f base, verifying all 60 CPU/integration RTL/header hashes against
the retained functional evidence. It does not promote either source set.
`prepare.py 5l` promotes exactly two RTL files and appends upstream patch0081;
after that commit, `prepare.py banked` promotes exactly seven RTL files and
appends patch0082 for the ZAP changes. ARM920 modules are maintained locally.
Do not rerun promotion after its corresponding commit.

Run `patches/zap/verify.sh` into the variant's `replay.log` before publication.
`publish.py VARIANT` stages only its explicit scope, verifies the 178 effective
inputs against the prior fit, creates a GitHub commit using `gh`, updates local
and remote master, then dispatches once with seed42/debug-on. It refuses an
existing publication receipt. Never dispatch the banked variant until the
control has completed. The normal and public remote names alias the same repo.

`collect.py VARIANT RUN` waits for no jobs itself: it accepts only completed runs
of the exact published commit, downloads both artifacts, checks immutable source,
QSF, clocks, exception preservation, SDRAM registers, bitstream and eight timing
corners, and records native TLB RAM implementation and resource hierarchy.
A failed timing gate is recorded as evidence, not an artifact collection failure.
All generated files live in `build/fit/tlb-matched-20261117/`.

The published third-slot follow-up uses its own input and publication receipts
under `build/fit/banked-third-20261118/`. Collect its existing run and compare
with the verified banked control using the commands below.

```sh
python3 tools/tlb_matched_fit/collect.py banked-third 44258633306
python3 tools/tlb_matched_fit/compare_third.py
```

GitHub operations require authenticated `gh`; no browser, remote git transport,
worktree, new branch, hardware deployment or extra optimization is involved.
