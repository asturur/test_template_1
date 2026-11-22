#!/bin/sh
# Run from the repository root with the installed offline simulator.
set -eu
out=build/sim/timing-isolation-smoke
fixture=tools/fit_isolation
stage="$out/board-project"
mkdir -p "$stage/rtl" "$stage/$fixture"
cp Template.qsf files.qip "$stage/"
cp rtl/ngage_cpu.sv rtl/ngage_upp.v "$stage/rtl/"
cp "$fixture/board_master.vh" "$stage/$fixture/"
python3 "$fixture/prepare.py" --project "$stage" --mode board-only

docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w /work --entrypoint /bin/sh jotego/simulator:arm64 -c '
    set -eu
    out=$1
    fixture=$2
    stage=$3
    verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint -DNGAGE_ARM9V2 -DNGAGE_BLOCK_WRITEBACK \
        --top-module cpu_isolation_smoke --Mdir "$out/cpu-obj" "$fixture/cpu_isolation.v" \
        "$fixture/cpu_smoke.v" rtl/ngage_cpu.sv rtl/arm9v2/arm925t_phone.v \
        rtl/arm9v2/upstream/sim/stubs/*.sv > "$out/cpu-build.log" 2>&1
    "$out/cpu-obj/Vcpu_isolation_smoke" > "$out/cpu-run.log" 2>&1
    grep "^PASS" "$out/cpu-run.log"

    verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint \
        --top-module board_isolation_smoke --Mdir "$out/board-obj" "$stage/$fixture/board_master.sv" \
        "$stage/rtl/ngage_upp.v" "$fixture/board_smoke.v" > "$out/board-build.log" 2>&1
    "$out/board-obj/Vboard_isolation_smoke" > "$out/board-run.log" 2>&1
    grep "^PASS" "$out/board-run.log"
' smoke "$out" "$fixture" "$stage"
