# Asphalt Urban GT race profile on MiSTer

On 17 November 2026, a passive capture on the operator-reported 5F core collected 298 snapshots across 74.5 seconds of core time at 78 MHz. Screenshots near the start and during the capture showed lap 2 of 3 in progress. The recorder reported tag `261117`, reset generation 3, and one missing sequence. The date tag alone cannot identify the build commit.

| Original ARM loop, inclusive E32 code offsets | Fetch-PC samples | Share |
|---|---:|---:|
| 0x56d3c–0x56da0, table lookup and two multiplies for pixel coordinates | 52 | 17.4% |
| 0x56eb4–0x56efc, two halfword lookups and a bitwise combine | 11 | 3.7% |
| 0x56f30–0x56f5c, single indexed halfword lookup | 12 | 4.0% |
| **Combined** | **75** | **25.2%** |

All three loops compare a pixel value against 0xf000, conditionally write a halfword and advance the destination by two bytes. The largest loop reads a table value that feeds both multiplies, selects between two source pointers and conditionally advances three coordinates at the loop back edge. These operations identify a second original rendering workload for measuring a change that helps the Super Monkey Ball span loop. A future replay should validate both outcomes of the conditional write, preserve skipped pixels, and score cycles per pixel visited.

The sampled addresses use the last fetch PC, which can remain visible during stalls. A sample at the back edge cannot by itself measure a branch penalty. These percentages describe this race window. It has no frame boundaries or retired-instruction trace.

## Executable and address checks

The local ignored fixture `tests/cpu/asphalt_urban_gt/local/6R67.app` came from `/SYSTEM/APPS/6R67/6R67.APP` inside the user's Asphalt Urban GT card image. It is 642,196 bytes with SHA-256 `41b55148917bae5c48bcb3985c225fac9bcb81a7714e9b889b6bd892a170bf84`. E32 code starts at file offset 0x7c. Matching sampled instruction words places it at runtime base 0xfff00000. Of 222 PCs within that range, 150 words matched at the reported address, 65 matched the following word and 7 were range-only. The other 76 PCs were in the firmware ROM window. Each listed loop had exact matches at multiple distinct PCs.

All three loops have checked offline replays of the captured instructions. The fixtures validate both texture choices, unchanged skipped destinations and fixed-work cycles per pixel visited. [Matched Asphalt results](cpu-third-data-mapping.md)

[PC histogram, counters and provenance](evidence/asphalt-urban-gt-5f-20261117.json) · [Super Monkey Ball comparison](super-monkey-ball-profile.md)
