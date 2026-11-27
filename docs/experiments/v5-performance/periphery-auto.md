# Automatic periphery placement at 104 MHz

The [QSF patch](patches/periphery-auto.patch) applies to `bbed9e4`,
which has the exact retained `e9552bd` tree. The trial `bffd426`
switches the global periphery-to-core placement setting from `ON`
to `AUTO`. Quartus then selects timing-sensitive periphery transfers
for early placement. The retained setting requests early placement
for all of those transfers. Altera recommends using `ON` on specific
instances instead of setting it globally.
[Quartus Standard settings reference](https://docs.altera.com/r/docs/d815780/17.1/quartus-prime-standard-edition-settings-file-reference-manual/periphery_to_core_placement_and_routing_optimization)

## Target and baseline

The target is worst setup slack of −1.500 ns or better at physical
104 MHz. The November 24 retained seed 13 has −2.061 ns worst setup.
Its hot report lists 297 paths below the target, including 111 UPP
peripheral paths and 32 Wishbone merger paths. The cold report lists
107 paths below the target. Routing takes 8.739 ns of the hottest
seed 13 data path's 10.925 ns after launch. The overall path count and
the variety of endpoints motivated a placement experiment on the
whole retained design.

Quartus generates `build_id.v` during compilation. Its date enters the
MiSTer version string and build tag, and the donor recorded a change
in timing between otherwise identical source and seed on different
build dates. The matched control here uses the exact retained source
tree at `81a1b45`, built on the same date as the candidate. Compare
the generated build date in the compile log, every effective QSF,
the compiled source hashes and the reported Fitter setting.
[Donor seed sweep](https://github.com/jakesjews/NGage_MiSTer/commit/9210fa2620)

## Runs

Both production triplets use DDR debugging off. Check the three
matched seeds and all four corners, plus the SDRAM pin-register gate.

| Seed | Same-day control | Automatic placement |
| ---: | --- | --- |
| 43 | [Control](https://github.com/asturur/test_template_1/actions/runs/45771267820) | [Auto](https://github.com/asturur/test_template_1/actions/runs/45771099927) |
| 13 | [Control](https://github.com/asturur/test_template_1/actions/runs/45771268571) | [Auto](https://github.com/asturur/test_template_1/actions/runs/45771100820) |
| 31337 | [Control](https://github.com/asturur/test_template_1/actions/runs/45771266151) | [Auto](https://github.com/asturur/test_template_1/actions/runs/45771099906) |

## Independent refill RAM trial

The archived [refill M10K patch](patches/refill-m10k.patch) applies
directly to the retained tree. Commit `5b29095` keeps the original
placement setting and replaces the refill staging registers with odd
and even M10K banks. The existing read prefetch and write bypass preserve
first-word and streaming ACK edges. The silicon cache configuration
remains 16 KiB each for I and D. The older fits saved 1,138–1,198 ALMs
for two M10Ks and lost 0.044 ns of median setup. The new fit tests that
area trade on the current retained sources and build date.
[Original area results](../../v5-alm-storage-results.md)

Both directed collision modes pass on the retained tree. The 105 fixed
windows, four native PolyCount frames and all 171,496 mixed events
match exactly. [Current-tree qualification](../../evidence/v5-104-refill-m10k-retained.json)

The independent 104 MHz fits use seeds 43, 13 and 31337 and compare to
the same-day retained triplet above.
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45772369046) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45772367974) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45772369016)

## Results

All nine builds report generated build date `261126`. The three
same-day `ON` fits reproduce the November 24 timing. The `AUTO`
fits report the requested setting in Quartus and produce the same
bitstream as `ON` on every paired seed. The study verifies the effective
QSFs and all 133 compiled input hashes. The refill fit changes only
the CPU wrapper among those inputs.

| Seed | Retained setup (ns) | Auto setup (ns) | M10K refill setup (ns) | Refill ALMs saved |
| ---: | ---: | ---: | ---: | ---: |
| 43 | −2.508 | −2.508 | −2.431 | 78 |
| 13 | −2.061 | −2.061 | −2.434 | 19 |
| 31337 | −2.471 | −2.471 | −2.814 | 75 |

Refill has a 0.037 ns better median worst setup and loses 852.272 ns
of median core setup TNS. It saves 60 median ALMs and uses two more
M10Ks. Seed 43 falls from 441 to 135 hot paths below −1.5 ns,
while the other two seeds show more paths below the target. The best
retained slack remains −2.061 ns. Every fit produces an RBF, misses
setup and keeps all 16 SDRAM DQ pins registered for input, output and
output enable. Public `11c4a0c` restores the exact retained tree.
[Verified paths and bitstream receipts](../../evidence/v5-104-periphery-auto-fits.json)
