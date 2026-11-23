#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
out=build/sim/arm9v2-ras
mkdir -p "$out"

git show 29479fecc32fe8a787378222f1ac2010a0eaf8a7:rtl/arm9v2/arm925t_phone.v | awk '
    /^module ngage2_arm9v2_predict / { active = 1; sub(/ngage2_arm9v2_predict/, "reference_predict") }
    active { print }
    active && /^endmodule/ { exit }
' > "$out/reference.v"
grep -q '^module reference_predict' "$out/reference.v"

docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -ec '
        src=tests/cpu/arm9v2_ras
        out=build/sim/arm9v2-ras
        for mode in 1 0; do
            verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint --top-module tb \
                -GTOP_REGISTER="$mode" --Mdir "$out/obj-$mode" rtl/arm9v2/arm925t_phone.v \
                "$out/reference.v" "$src/tb.sv" > "$out/build-$mode.log" 2>&1
            "$out/obj-$mode/Vtb" > "$out/run-$mode.log" 2>&1
            grep "^PASS" "$out/run-$mode.log"
        done
    '
