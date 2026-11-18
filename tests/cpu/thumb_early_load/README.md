# Isolated Thumb early-load qualification

The overlay applies to exact published unbanked 5L. It promotes only
normalized single original Thumb immediate and SP-relative word loads to the
existing private lookup, P1 start and registered late ADD/CMP operand paths.
The comparison validates all 60 original CPU/integration RTL hashes before
applying the three-file patch.

Use unique output names and the installed offline `jotego/simulator:arm64`
image. The standard workloads use the established original payload fixtures.
The scoreboard needs the two earlier archived 5L runs and the fresh passive
control, which reproduces their counters before using their saved rows.

```sh
python3 tests/cpu/thumb_early_load/build.py control CHECK-CONTROL
python3 tests/cpu/thumb_early_load/build.py thumb CHECK-THUMB
python3 tests/cpu/tlb_three_mapping/run.py --name CHECK-CONTROL-WORK --build CHECK-CONTROL --suite jpeg --suite stream --suite games
python3 tests/cpu/tlb_three_mapping/run.py --name CHECK-THUMB-WORK --build CHECK-THUMB
python3 tests/cpu/thumb_early_load/build.py thumb CHECK-THUMB-SCAN --full-scan
python3 tests/cpu/tlb_three_mapping/run.py --name CHECK-SCAN-WORK --build CHECK-THUMB-SCAN --suite scan --workers 2
python3 tests/cpu/thumb_early_load/directed.py CHECK-DIRECTED-CONTROL --build CHECK-CONTROL
python3 tests/cpu/thumb_early_load/directed.py CHECK-DIRECTED-THUMB --build CHECK-THUMB --thumb
```

The banked fit follows a separate published source identity. The smoke runs
exercise both Monkey Ball patterns in both memory layouts, all four JPEG
cases and the ARM stream. The directed banked test deliberately removes the
revocation of the oldest local grant at delayed architectural fill commit.

```sh
python3 tests/cpu/thumb_early_load/build.py banked-third CHECK-BANKED
python3 tests/cpu/tlb_three_mapping/run.py --name CHECK-BANKED-WORK --build CHECK-BANKED --suite monkey --suite jpeg --suite stream
python3 tests/cpu/thumb_early_load/banked_unit.py CHECK-DELAYED --build CHECK-BANKED
```

The archived run names are pinned in `report.py`; rerun with different names
by updating those receipt paths. The report matches retired PC/store
fingerprints and checks the original paired JPEG consumers by retirement
ordinal. The common benchmark PC journal subtracts eight. The analysis
recovers true Thumb addresses by adding four on classified Thumb events,
and the directed observer uses the architectural four-byte bias directly.

[Results and decision](../../../docs/cpu-thumb-early-load.md)
