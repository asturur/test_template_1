# Production full-product multiplier

Run `sh tests/cpu/multiply_mapping/run.sh` from the repository root. Uses the
existing offline simulator container and private build/sim/unit-multiply-mapping
outputs; does not touch other simulations or the phone.

The frozen pre-change multiplier is a test-only busy/flags comparison, never
selected by the production QIP. A separate Python integer oracle checks 2,048
edge/random signed/unsigned accumulating products and 4,096 ordered low/high
results, including random holds, failed conditions and 16 held cancellations.
Expected arithmetic does not come from the reference RTL. The source license is preserved; the enum macro is expanded to its exact
`XX = 'X` definition for the formatter.

Production CPU/payload qualification is recorded in docs/dsp-mapping-audit.md.
Functional equivalence does not establish Quartus DSP packing, ALM savings or
routed timing; those remain physical-build gates. Busy latency is unchanged.
