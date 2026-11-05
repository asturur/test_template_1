#!/bin/sh
set -eu
mkdir -p build/sim/unit-trace-sink
iverilog -g2012 -s tb -o build/sim/unit-trace-sink/test rtl/ngage_trace_sink.v tests/phone/trace_sink/tb.sv
vvp build/sim/unit-trace-sink/test
