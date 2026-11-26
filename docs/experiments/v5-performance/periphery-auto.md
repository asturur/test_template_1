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
