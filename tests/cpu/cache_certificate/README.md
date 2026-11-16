# Checked-line reuse working set

The generated fixture extends the maintained resident-cache memory oracle.
It preloads12different lines, learns/revisits8, wraps capacity with stores,
checks all values in reverse order and revokes all facts on invalidation.
The original lane, physical writeback, high-tag, class and reset cases remain.

Run `sh tests/cpu/cache_certificate/run.sh build/sim/UNIQUE`.
`CACHE_ACCESS_RTL=PATH` selects an isolated source; `CERT_REUSE=0` checks the
previous2-entry implementation and8checks the adopted8-entry implementation.
These are test controls, not production build options. The baseline and candidate
both must return correct data. The expected short-hit count separately verifies
capacity. A broken slot selector is rejected by data equality before that count.
