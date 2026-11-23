#!/bin/bash
set -eu
cd "$(dirname "$0")/../../.."
root="$PWD"
base=341a45421019398c2a44bf6f9ce79d312e0cdbac
output=build/sim/arm9v2-store-ordering
mkdir -p "$output"
run_dir=$(mktemp -d "$output/run.XXXXXX")
git archive "$base" rtl/ngage_cpu.sv rtl/ngage_upp.v rtl/arm9v2/upstream/sim/stubs \
    sim/programs/link.ld tests/cpu/arm9v2_board | tar -xf - -C "$run_dir"
git show "$base:rtl/arm9v2/arm925t_phone.v" > "$run_dir/parent.v"
cp rtl/arm9v2/arm925t_phone.v "$run_dir/candidate.v"

cd "$run_dir"
patch -s -p1 < "$root/tests/cpu/arm9v2_store_queue/ordering.patch"
for leg in parent candidate; do
    ARM9V2_NETLIST="$leg.v" ARM9V2_HALF_WRITEBACK=1 \
        sh tests/cpu/arm9v2_board/run-contract.sh "$leg" > "contract-$leg.log" 2>&1
done
for case in burst-0-wait-0 burst-0-wait-5 burst-1-wait-0 burst-1-wait-5; do
    reference="build/sim/arm9v2/contract-parent/$case.log"
    candidate="build/sim/arm9v2/contract-candidate/$case.log"
    test "$(grep -c '^POST ' "$candidate")" -eq 10
    diff -u <(grep -E '^(POST|PASS) ' "$reference") <(grep -E '^(POST|PASS) ' "$candidate")
    grep '^PASS ' "$candidate"
done
printf 'PASS posted-store issue and drain ordering in %s\n' "$run_dir"
