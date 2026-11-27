# SDRAM block-payload candidates after the dirty descriptor

The [SDRAM block-payload patch](patches/sdram-block-payload.patch) composes with either outcome of the dirty-descriptor fit. Both private candidates follow the public dirty-descriptor commit `dbad302dd2f85f5a1b016e472cd9557a58e19927`.

| Dirty verdict | Parent or forward restore | Payload candidate | Matched controls for seeds 13, 43, 31337 |
| --- | --- | --- | --- |
| Keep | `dbad302dd2f85f5a1b016e472cd9557a58e19927` | `f2949f6e1569b77e0ffc34fde4e4fbb478549c41` | 45850041608, 45850046593, 45850051512 |
| Park | `20fb1e537cad366cc700be0e4ff6c388c7563d91` | `b7cf9fcef0bf2ea2c1d29ec569b3c0d0a0dcf120` | 45824513460, 45824520116, 45824525843 |

The park restore has the exact timer tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. The confirmed production mode is physical 104 MHz with DDR debug off. Across all six seed/variant manifests, exactly `Template.sv` and `rtl/ngage_sdram_arbiter.v` differ from the corresponding control. The QSF bytes match by seed and control. The keep comparison uses the dirty build's effective-input preflight while its routed artifacts are pending. [Lineage verification](../../evidence/v5-104-sdram-payload-dirty-preflight.json) · [Paired inputs](../../evidence/v5-104-sdram-payload-dirty-paired-inputs.json)

## Exact combined replay

Candidate `f2949f6e` reproduces the previously qualified CPU and arbiter source hashes. The pinned CPU generator check passed for both exact source archives. The reference is the published dirty-descriptor commit.

The normal and timer/MMC/LCD overlap pin traces match 171,496 and 171,497 events at 1,201,547 and 1,201,528 clocks. The additional D-cache guest dirties and evicts one line and checks its contents. Both pin traces match 172,060 events at 1,204,706 clocks, including two CPU writes that carry the correct packed 128-bit payload on every lane.

All 105 fixed windows and four native frames match the exact dirty-descriptor workload receipts. Both benches explicitly enable the production arbiter capture. Verilator source fingerprints match the two active implementations across the fixed, native and pin replays. [Qualification receipt](../../evidence/v5-104-sdram-payload-dirty-combined.json)

## Reproduction

Restore scripts from the [replay patch](patches/sdram-payload-dirty-combined-replay.patch) at the repository root. The payload qualification supplies the targeted guest binary and the fixed-window observers. The dirty-descriptor qualification supplies the prior mixed deck and timer-overlap guest.

```sh
payload=scratch/v5-fit-loop/sdram-block-payload
area=scratch/v5-fit-loop/sdram-payload-dirty-combined
python3 -B "$payload/prepare-followup.py" --active-tip dbad302dd2f85f5a1b016e472cd9557a58e19927
python3 -B "$payload/followup-20261126/verify-matched-inputs.py"
python3 -B "$payload/prepare-block-guest.py"
sh "$area/stage.sh"
sh "$area/qualify.sh"
python3 -B "$area/record.py"
```
