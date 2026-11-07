#!/bin/sh
set -eu
mkdir -p build/sim/unit-test-sim
g++ -std=c++17 -O2 -Iscratch/simif-investigation tests/phone/card_fixture/reference.cpp -o build/sim/unit-test-sim/reference
build/sim/unit-test-sim/reference
iverilog -g2005 -s tb -o build/sim/unit-test-sim/test rtl/ngage_test_sim.v tests/phone/card_fixture/tb.v
vvp build/sim/unit-test-sim/test > build/sim/unit-test-sim/run.log
cat build/sim/unit-test-sim/run.log
grep -q '^PASS diagnostic SIM' build/sim/unit-test-sim/run.log

iverilog -g2005 -s tb -o build/sim/unit-test-sim/overflow rtl/ngage_test_sim.v tests/phone/card_fixture/overflow.v
vvp build/sim/unit-test-sim/overflow > build/sim/unit-test-sim/overflow.log
cat build/sim/unit-test-sim/overflow.log
grep -q '^PASS diagnostic SIM bounded FIFO' build/sim/unit-test-sim/overflow.log
