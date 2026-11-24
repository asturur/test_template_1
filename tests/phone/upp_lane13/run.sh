#!/bin/sh
set -eu
reference=${1:?source directory containing the unmodified RTL}
out=${UPP_LANE13_OUT:-build/sim/unit-upp-lane13}
mkdir -p "$out"
for keypad in 0 1; do
    for leg in reference trial; do
        if [ "$leg" = reference ]; then
            source=$reference
            set -- -DREFERENCE
        else
            source=.
            set --
        fi
        binary="$out/$leg-$keypad"
        iverilog -g2012 -s tb -Ptb.KEYPAD_ENABLE="$keypad" "$@" \
            -y "$source/rtl" -I "$source/rtl" -o "$binary" \
            "$source/rtl/ngage_upp.v" "$source/rtl/ngage_upp_euart.v" \
            tests/phone/upp_lane13/tb.sv
        vvp "$binary" > "$binary.log"
        grep -E '^(TRACE|SAMPLE|DONE|PASS) ' "$binary.log" > "$binary.trace"
    done
    cmp "$out/reference-$keypad.trace" "$out/trial-$keypad.trace"
    grep '^PASS ' "$out/trial-$keypad.trace"
done
