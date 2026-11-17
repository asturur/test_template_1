# Single master5B fit collection

Run `python3 tools/cpu_owner_split_fit/collect.py` after run44001480657 finishes.
The collector uses gh only, never submits a fit, never creates refs or deploys,
and keeps log/RBF artifacts in separate run-named directories. It checks exact
commit/seed/debug provenance, all178 selected hashes, the unchanged physical
78MHz PLL/production BRAM/effective QSF, unique cache definitions, all eight
78/104 scenarios and clock/exception preservation before recording evidence.
The production workflow records inputs generically with record_fit_inputs.py;
it is not pinned to this historical candidate or any old payload hashes.
