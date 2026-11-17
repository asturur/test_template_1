# Step5A hardware build — 17 November 2026

**The 78MHz bitstream was generated and collected successfully. Timing is red.**
The full compile, postcompile input manifest,78/104MHz analyses, SDRAM pin-register
check and both uploads passed. Only `Require passing timing` failed. No retry,
deployment, phone access or5B experiment was performed.

- [Verified ngage1.rbf](../build/fit/frontend-5a-20261117/rbf-43985572525/ngage1.rbf)
- [Build identity](../build/fit/frontend-5a-20261117/rbf-43985572525/build-info.json)
- [Fitter summary](../build/fit/frontend-5a-20261117/quartus-logs-43985572525/output_files/Template.fit.summary)
- [Normal78MHz timing](../build/fit/frontend-5a-20261117/quartus-logs-43985572525/output_files/Template.sta.summary)
- [104MHz hot routed paths](../build/fit/frontend-5a-20261117/quartus-logs-43985572525/output_files/timing/resident-store/104/corner-1/setup.rpt)
- [Actual selected inputs](evidence/cpu-frontend-delivery-fit-inputs-20261117.json)
- [Resources, all eight corners and artifact proof](evidence/cpu-frontend-delivery-fit-20261117.json)

RBF **4,600,916 bytes**, SHA256
`8940a35518d6a61b36fe45b08f6bcfb4c8a056c6daeb4d0a1653bccbde250068`.

[Existing run43985572525](https://github.com/asturur/test_template_1/actions/runs/43985572525)
used commit`966270d981b0362412d055c0720a76db6ed4aca1`, tag
`fit-only/cpu-5a-20261117-s42-01`, matched3D parent
`418f6f824ab2e3353f71692382770433d5f0c093`, seed42 and debugger enabled.
All15 expected qualified RTL payloads match the passing simulation source
`1ddc7653903458d33e765e26bad69e1c8d817b2cab0920320b48d251ab2cb643`.
All178 actual selected-input SHA256 values match3D plus those payload
substitutions;13 selected design files differ. The complete effective QSF is
identical to3D, including tool-written Lite metadata. Physical PLL, QIPs, SDCs
and production BRAM match. The104MHz scenario changes analysis constraints,
not the78MHz physical PLL. Artifact build-info independently matches commit,
run, seed and debugger. Collection used `gh` only.

| Whole-chip resource | Stop3D | Step5A | Delta |
| --- | ---: | ---: | ---: |
| ALMs needed | 39,549 | **41,147** | +1,598 |
| Placed ALMs | 40,474 | **40,981** | +507 |
| Registers | 45,104 | **45,095** | −9 |
| Design registers | 41,622 | 41,776 | +154 |
| Routing registers | 3,363 | 3,200 | −163 |
| M10Ks | 503 | **502** | −1 |
| DSPs | 41 | **41** | 0 |
| Occupied LABs | 4,182 | 4,187 | +5 |
| MLABs | 40 | 40 | 0 |

Only four of4,191 LABs are empty. ALMs needed exceed the40,450 planning screen
by697; placed and needed counts are distinct. M10Ks leave19 to the521 planning
stop. The RAM count is a fitted result, not a cache-capacity change.

| Routed global setup, ns | Stop3D | Step5A | Delta |
| --- | ---: | ---: | ---: |
| 78MHz slow100C | −0.553 | **−1.970** | −1.417 |
| 78MHz slow−40C | −0.306 | **−1.668** | −1.362 |
| 104MHz slow100C | −3.758 | **−5.175** | −1.417 |
| 104MHz slow−40C | −3.511 | **−4.873** | −1.362 |

Normal78MHz CPU TNS is−304.683ns, versus3D−2.933ns; CPU hold stays positive
at+0.213ns. HDMI setup is−0.409ns versus3D+0.051ns. Across all scenario
corners, minimum hold is+0.088ns, removal+0.564ns, and minimum pulse+0.641ns
at78/+0.480ns at104. Recovery now passes, including+0.495ns hot104 versus
3D−0.210ns. Both frequency analyses preserve unrelated clocks and explicit
exceptions; scenario errors are empty. These are actual routed analyses.

The hot/cold limiting setup path is now
`zap_core|late_p1_ready~0_OTERM5518` → `cpu_inside.block_cpu~0_OTERM6340`.
Hot data delay is**14.041ns**,11 logic levels:4.000ns cells and10.042ns routing
(with−0.001ns interconnect correction). The late-data/admission decision still
reaches board CPU exclusion; this hardware gate needs future retiming. Offline
cycle gains do not establish timing closure.

The owner explicitly selected verified RBF+source/commit/PLL as the trigger for
mainline consolidation even with red timing. Production/index/hardware inputs
were unchanged through collection; subsequent exact-payload promotion and
single-master history reconciliation are recorded separately. No bitstream
has been deployed. Keep the fit tag and these artifacts as build provenance.

Replay the read-only audit with:

```sh
python3 tools/probe_retime_fit/collect.py \
  build/fit/frontend-5a-20261117/quartus-logs-43985572525 \
  --output build/fit/frontend-5a-20261117/summary.json
python3 tools/frontend_delivery_fit/verify.py
```
