# Joint TLB victim RAM and MMC FIFO after the refill trial

The [joint RAM patch](patches/tlb-victims-mmc-fifo.patch) maps both small-page TLB victim maps and the MMC host FIFO to RAM. It reproduces the three previously qualified source files from the archived component RTL and generator hunks. The independent native refill wrapper composes in either patch order.

| Refill result | Parent or forward restore | Joint RAM candidate | Controls for seeds 13, 43, 31337 |
| --- | --- | --- | --- |
| Keep | `99299836993ad77d812d314c78134ef6727d913e` | `b9e13fcc302434845a026b133b15428ce967b055` | 45863520207, 45863524825, 45863528948 |
| Park | `6db50edb2d93d4f1487d3bd5cf6ba295c4ea0277` | `ae3654c75c4ff5027d0bd146baf3c8f5f2280cde` | 45824513460, 45824520116, 45824525843 |

The restore has the exact timer tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. All six preflights verify the 133 selected source hashes at 104 MHz with DDR debug off. Only the generated CPU and MMC host differ from the respective selected controls, and the generator is outside Quartus's selected graph. [Preflight receipt](../../evidence/v5-104-tlb-fifo-refill-preflight.json)

## Combined replay

The exact combined tree passes the pinned generator and the focused TLB walker and MMC host/FIFO cases. All four ARM9v2 board profiles match, as do all 105 fixed windows and four native frames. The fixed and native decks enable native CPU refill. The 114-source mixed pin deck uses scalar CPU and native LCD, including both the normal and timer/MMC/LCD overlap traces at 171,496 and 171,497 events. Both exercise the actual MMC backing and card persistence. Mixed, fixed and native compilation manifests record the qualified CPU, MMC host and wrapper fingerprints. [Qualification receipt](../../evidence/v5-104-tlb-fifo-refill-combined.json)

## Reproduction

Restore the helpers from the [replay patch](patches/tlb-fifo-refill-combined-replay.patch). The sealed standalone qualifications supply the patches, directed fixtures, and frozen benchmark and pin-deck inputs. Use the cached Jotego image and the pinned ARM9 donor.

```sh
area=scratch/v5-fit-loop/tlb-fifo-refill-combined
python3 -B "$area/prepare-fit.py"
sh "$area/stage.sh"
sh "$area/qualify.sh"
python3 -B "$area/record.py"
```
