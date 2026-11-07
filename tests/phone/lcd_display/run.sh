#!/bin/sh
set -eu
mkdir -p build/sim/unit-lcd-display
iverilog -g2005 -s tb -o build/sim/unit-lcd-display/test rtl/ngage_bram.v rtl/ngage_lcd_display.v tests/phone/lcd_display/tb.v
vvp build/sim/unit-lcd-display/test > build/sim/unit-lcd-display/run.log
cat build/sim/unit-lcd-display/run.log
grep -q '^PASS diagnostic raster' build/sim/unit-lcd-display/run.log
iverilog -g2005 -s tb -o build/sim/unit-lcd-display/bands rtl/ngage_bram.v rtl/ngage_lcd_display.v tests/phone/lcd_display/bands_tb.v
vvp build/sim/unit-lcd-display/bands > build/sim/unit-lcd-display/bands.log
cat build/sim/unit-lcd-display/bands.log
grep -q '^PASS partial and out-of-order' build/sim/unit-lcd-display/bands.log

iverilog -g2005 -I. -s tb -o build/sim/unit-lcd-display/protocol rtl/ngage_bram.v rtl/ngage_lcd_display.v tests/phone/lcd_display/protocol_tb.v
vvp build/sim/unit-lcd-display/protocol > build/sim/unit-lcd-display/protocol.log
cat build/sim/unit-lcd-display/protocol.log
grep -q '^PASS LCD cold-boot' build/sim/unit-lcd-display/protocol.log
