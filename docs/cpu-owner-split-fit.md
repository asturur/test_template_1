# Step5B matched master fit —17 November2026

**Retain5B: better timing and fewer ALMs, with zero cycle cost. Timing remains red.**

[Run44001480657](https://github.com/asturur/test_template_1/actions/runs/44001480657)
fits exact master **419471d5cf85d2ca9d4cf6ff68a9652a1253ffd1**, seed42,
debugger enabled. [Verified RBF](../build/fit/cpu-owner-split-20261117/ngage1-rbf-44001480657/ngage1.rbf) ·
[Build identity](../build/fit/cpu-owner-split-20261117/ngage1-rbf-44001480657/build-info.json) ·
[All178 inputs](evidence/cpu-owner-split-fit-inputs-20261117.json) ·
[Resources/corners/artifact audit](evidence/cpu-owner-split-fit-20261117.json).

RBF **4,566,388 bytes**, SHA256
`22aeed19b11f787816689b33be4b083e9f6a8c8706887b99f8deedd2b23a920d`.
Compile, actual source manifest, eight routed scenarios, SDRAM pin registers
and both uploads pass. Only timing acceptance fails. All178 selected hashes
match5A plus four qualified5B RTL substitutions. Complete effective QSF, QIPs,
SDCs, production BRAM and physical78MHz PLL match5A.104MHz is analysis only.
The generic master workflow records actual inputs without old payload pins
and runs the validated report Tcl on this same fitted database. Unrelated
clocks and exceptions are unchanged; no timing exception masks a path.

| Resource | 5A | 5B | Delta |
| --- | ---: | ---: | ---: |
| ALMs | 41,147 | 40,828 | -319 |
| placed_ALMs | 40,981 | 40,814 | -167 |
| registers | 45,095 | 45,279 | +184 |
| design_registers | 41,776 | 42,041 | +265 |
| routing_registers | 3,200 | 3,119 | -81 |
| M10Ks | 502 | 502 | +0 |
| DSPs | 41 | 41 | +0 |
| occupied_LABs | 4,187 | 4,188 | +1 |
| MLABs | 40 | 40 | +0 |

ALMs needed40828 exceed the40450 planning screen by378. Packing remains
severely constrained:4188/4191 LABs occupied, **three free**, versus four in5A.
Fewer ALMs did not free a LAB. RTL adds zero logical state, while fitted
register implementation/replication changes total registers by+184. Cache
capacity, M10Ks and DSPs are unchanged.

| Routed global setup | 5A ns | 5B ns | Improvement ns |
| --- | ---: | ---: | ---: |
|78MHz slow100C |−1.970 |**−1.258** |+0.712 |
|78MHz slow−40C |−1.668 |**−1.121** |+0.547 |
|104MHz slow100C |−5.175 |**−4.463** |+0.712 |
|104MHz slow−40C |−4.873 |**−4.326** |+0.547 |

Normal78MHz CPU TNS improves−304.683→**−28.437ns**. The reported negative
hot78 endpoints fall715→65; none of the203 former late_p1_ready origins remain
in the negative list. HDMI setup improves−0.409→+0.024ns. All eight corners
keep positive hold/recovery/removal/pulse: minima+0.115 hold,+0.140 recovery
(hot104),+0.342 removal, pulse+0.641 at78/+0.480 at104.

The new worst hot path is adapter `select_probe_p1~2_OTERM12162` →
`comb~26_OTERM14475`, **13.679ns**,12 levels:4.537ns cells+9.142ns routing.
Actual hops are probe-address selection → cache tag matching → probe priority/
way selection → probe_read_collision → probe_result_tag coverage → adapter
selection/coverage feedback. Reported retimed nodes identify the local private
probe selection/coverage boundary still needing timing work. The old late
owner/address→req_ready→CPU exclusion family is no longer the limiting path.

Next physical action: bound/register private tag/way/collision/coverage ownership
before adapter selection feedback, keeping admission/fault/probe qualification.
Measure cycle cost and avoid duplicating a wide CAM at this packing. Do not
mask the path. The remaining miss does not gate authorized offline throughput.

Matched workloads stay matrix50033, transpose3591, JPEG84353 and drained stream71
at both memory profiles, with exact retirement/memory schedules. Zero cycle
cost,319 fewer ALMs and material setup/TNS improvement justify retaining5B
despite one fewer free LAB. [Implementation](cpu-owner-split.md).
[Subsequently accepted5C gain](cpu-product-bypass.md) is **not in this RBF**.
No second fit, fit-only ref, deployment or phone command was issued.

Replay collection: `python3 tools/cpu_owner_split_fit/collect.py`.
