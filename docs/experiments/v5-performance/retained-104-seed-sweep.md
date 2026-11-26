# Retained 104 MHz seed sweep and timing follow-up

The retained clock and HDL tree is `e9552bd`. `11c4a0c` and `81a1b45`
both have the identical Git tree. Build date, original HDL, 16 KiB
per cache, physical 104 MHz clock and DDR debugging off are fixed.
The −1.5 ns milestone tracks progress. Timing closure requires
nonnegative setup, hold, recovery, removal and minimum pulse width
over the native routed corners and the SDRAM pin-register check.

| Seed | Run |
| ---: | --- |
| 1 | [45780077300](https://github.com/asturur/test_template_1/actions/runs/45780077300) |
| 2 | [45780081579](https://github.com/asturur/test_template_1/actions/runs/45780081579) |
| 3 | [45780077827](https://github.com/asturur/test_template_1/actions/runs/45780077827) |
| 4 | [45780074613](https://github.com/asturur/test_template_1/actions/runs/45780074613) |
| 5 | [45780076796](https://github.com/asturur/test_template_1/actions/runs/45780076796) |
| 6 | [45780082010](https://github.com/asturur/test_template_1/actions/runs/45780082010) |
| 7 | [45780082099](https://github.com/asturur/test_template_1/actions/runs/45780082099) |
| 13 | [45771268571](https://github.com/asturur/test_template_1/actions/runs/45771268571) |
| 43 | [45771267820](https://github.com/asturur/test_template_1/actions/runs/45771267820) |
| 31337 | [45771266151](https://github.com/asturur/test_template_1/actions/runs/45771266151) |

## Routed results

All ten builds produced an RBF. Fit provenance confirms the same
production source tree and generated build date (`261126`). Seed is
the only changed effective assignment. All ten pass the hold, recovery,
removal, minimum pulse width and SDRAM I/O register checks. All ten
fail setup at 104 MHz, with worst setup from −2.905 to −2.061 ns and a
median of −2.598 ns. Seed 13 is best by both worst slack and total
negative core setup slack. It has 297 paths below −1.5 ns hot and
107 cold. Both cutoffs include every path below that threshold.

| Rank | Seed | Worst setup (ns) | Core setup TNS (ns) | ALMs | Limiting path |
| ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 13 | −2.061 | −4606.649 | 36,420 | UPP request address to lane-13 UART response |
| 2 | 31337 | −2.471 | −5143.651 | 36,461 | SDRAM scheduler readiness through posted ACK to Wishbone merger address |
| 3 | 4 | −2.473 | −5086.712 | 36,489 | Native refill received count to Wishbone merger address |
| 4 | 43 | −2.508 | −5288.569 | 36,446 | UPP request address to lane-13 UART response |
| 5 | 6 | −2.579 | −5455.505 | 36,375 | D-side TLB walk to D-cache live-hit trust |
| 6 | 5 | −2.616 | −5509.917 | 36,550 | Fetch address to I-cache fill readiness |
| 7 | 1 | −2.631 | −5484.046 | 36,475 | DMA destination width to queued descriptor RAM |
| 8 | 2 | −2.720 | −6198.163 | 36,424 | D-cache bank RAM to checked cache word |
| 9 | 3 | −2.870 | −6954.138 | 36,462 | D-cache strobe to Wishbone merger line candidate |
| 10 | 7 | −2.905 | −5967.618 | 36,381 | SDRAM scheduler readiness through posted ACK to Wishbone merger address |

The retained best RBF is `build/fit/v5-104mhz-81a1b45-seed13/ngage1.rbf`,
SHA-256 `46e6e28a4ec926271331ebe0a6d747186b428beedab38773181fa0a5951dfb6a`.
It remains an experimental build with a failing setup gate.
[Full native corner results, route witnesses and bitstream hashes](../../evidence/v5-104-retained-sweep.json)

## Timing investigation during the sweep

At the hot corner on seed 13, 81 of 111 UPP peripheral paths below
−1.5 ns launch from the reset-drain duplicate. The main fanout reaches
the request-stage CYC and then the timer, ICU and keypad state-update
gates. Its worst timer path is −1.931 ns. The lane-13 UART return at
−2.061 ns starts at a captured address bit and is distinct. The same
seed has 32 paths below −1.5 ns ending at the Wishbone merger.

The MMC byte-count path is a smaller UPP target that appears on every
retained seed. It traverses bus acceptance and the wide `nfifo` increment.
The [prepared counter trial](mmc-count-prepare.md) splits that carry while
preserving the same MMC request and update edges. Fixed workloads, the
native frames, the mixed pin model and directed host tests measure the
prototype independently.

The [Wishbone reply split](wb-reply-class.md) takes SDRAM writes out
of the common reply that can feed I-cache next-request logic. The
posted-write route limits seed 31337 and seed 7, and is within 0.006 ns
of the worst setup on seed 13. The same path has a routed witness in
both slow models. In total four seeds are limited by distinct routes
ending at the Wishbone merger. The prototype preserves the D-cache
response and arbitration edges and matches all fixed, native and mixed
replays. Fit it on seeds 13, 43 and 31337 against the same source settings.
Check the named write-to-I-cache route and compare whole-core setup and
TNS. The prepared MMC counter is an independent follow-up if the MMC
endpoints remain prominent. Both prototypes still need routed timing.

The worst timer witness ends at timer 4's synchronous clear. The seed
13 hot report shows a 10.833 ns data path from reset drain through two
request-stage CYC cells, timer claim, write access and two count-control
cells. The timer decrement carry is outside this witness. If new fits
still expose it, capture the timer unit and write operation from the
incoming request alongside the held UPP packet. Qualify each prepared
operation with the existing live commit, so cancellation and write or
expiry priority stay on the original edge. Check coincident expiry,
reload, count writes, stop, invalid lanes and reset before fitting.

## Matched follow-up fits

Each row uses seeds 13, 43 and 31337 at physical 104 MHz.
Quartus computes the ALMs-needed estimate from final occupied ALMs,
recoverable dense packing, and unavailable ALMs. The Wishbone, lane
13 and live-trust builds occupied fewer physical ALMs in every matched
fit while the estimated number needed rose. [ALM accounting audit](fitter-alm-accounting.md)

| Trial | Best setup | Median setup | Median ALMs needed | Decision |
| --- | ---: | ---: | ---: | --- |
| Retained `e9552bd` tree | −2.061 ns | −2.471 ns | 36,446 | Keep |
| [Wishbone reply split](wb-reply-class.md) | −2.450 ns | −2.566 ns | 37,131 | Park |
| [MMC counter](mmc-count-prepare.md) | −2.765 ns | −2.811 ns | 36,017 | Park for area |
| [Lane 13](lane13-register-sources.md) | −2.895 ns | −3.029 ns | 37,247 | Park |
| [Tuner clock model](lltune-generated-clock.md) | −2.297 ns | −2.733 ns | 36,599 | Park the fit and preserve the verified model |
| [D-cache live trust](dcache-live-trust.md) | −2.632 ns | −2.703 ns | 37,157 | Park |
| [Prepared timer writes](timer-write-prepare.md) | −2.214 ns | −2.403 ns | 37,014 | Keep as the next experiment base |
