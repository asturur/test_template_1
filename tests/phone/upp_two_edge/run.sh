#!/bin/sh
set -eu
reference=$(realpath "$1")
out=${UPP_TWO_EDGE_TEST_OUT:-build/sim/upp-two-edge}
mkdir -p "$out"
for keypad in 0 1; do
    for leg in reference candidate; do
        set --
        source=.
        if [ "$leg" = reference ]; then
            source=$reference
            set -- -DREFERENCE
        fi
        prefix="$out/$leg-$keypad"
        iverilog -g2012 -s tb -Ptb.KEYPAD_ENABLE="$keypad" "$@" \
            -y "$source/rtl" -I "$source/rtl" -o "$prefix" \
            "$source/rtl/ngage_upp.v" "$source/rtl/ngage_upp_euart.v" \
            tests/phone/upp_two_edge/tb.sv
        if ! vvp "$prefix" > "$prefix.log"; then
            tail -20 "$prefix.log"
            exit 1
        fi
        sed -n 's/^DONE [0-9]* duration=[0-9]* //p; s/^SAMPLE [0-9]* //p' \
            "$prefix.log" > "$prefix.sequence"
        grep -E '^(APERTURE|PASS) ' "$prefix.log"
    done
    cmp "$out/reference-$keypad.sequence" "$out/candidate-$keypad.sequence"
done
