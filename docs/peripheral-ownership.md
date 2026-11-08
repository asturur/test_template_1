# Peripheral ownership and local RAM commands

This records the behavioral UPP model, not verified Nokia pin-level hardware.
All decoding uses the existing captured UPP bus in internal-CPU mode. Child
response priority, configuration, snooped effects and LCD DMA exclusion remain
in their existing modules. No new clock or timing exception is introduced.

## Regional RAM ownership

| Storage window | Local exclusions | Preserved behavior |
| --- | --- | --- |
| `0c03xxxx` upload | None | Keypad configuration gates access; legal GPIO byte lanes |
| `0c10xxxx` NOS/shared | MDI claim | MDI owns `01f4`, `01f8`, `03e8`, `03ec` |
| `0c150xxx` GPIO/SIM | SIMIF, NOS, GPIO loopback claims | Original `000..5ff` and `800..8ff` windows; `420/424` excluded in range decode for CBUS |
| `0c06ffxx` auxiliary upload | None | Existing auxiliary index, independent of upload/NOS/GPIO storage |
| `0c14xxxx` auxiliary windows | MDI claim | Existing `f0xx`, and first32 bytes of `2/8/a/b/c` pages; MDI at `b004` |
| `0c12xxxx` auxiliary windows | Boot claim | ICU-adjacent `0c00..0c1f`; `0034` remains a boot latch |
| `0c004xxx` NOS4K | Boot scratch claim | 45 latches at `4748..47f8`; remaining words use BRAM, including `47fc` |
| `0c000xxx` ASIC stub | Read-only | Existing `47704770` return; writes fault |
| `0dxxxxxx` sparse | Trace claim | Trace pages never allocate sparse entries |

ICU, timers, extra ICU/config registers and trace sinks do not overlap the
regional RAM windows above. Their claims therefore do not qualify RAM writes.
Upload RAM's write enable is now solely clearing or
`local_access && we && valid_lanes && cfg_keypad && upload_hit`; no boot/scratch
claim or aggregate GPIO selection feeds it. Each other RAM receives its own
regional qualifier. Aggregate GPIO selection is used only for the keypad
access overlay, not fed back into those write enables.

Dedicated read-response priority is unchanged. SIMIF's unclaimed GPIO injection
snoop at `0c150008` still observes the write while GPIO stores it. SIMIF claim
at `0c150800` and `0c1500b8` still depends on operation/lanes. Keypad read overlays
and GPIO quirks are unchanged. NOS4K retains its original unrestricted byte masks;
GPIO RAM retains its existing accepted lane combinations. Warm reset preserves
RAM, cold initialization clears it. BRAM reads retain their one-edge readiness;
this change adds no stage and does not alter acknowledgement/error decisions.

`tests/phone/regional_ownership/run.sh` compares regional selection with the
previous global exclusion using actual connected child claims across all words
in eight relevant64KiB windows, then checks operation/lane/config combinations
at the real overlaps. Board/SIM/DMA tests exercise the effects and overlays.
