#!/bin/sh
set -eu
out=build/sim/unit-shared-register-ram
mkdir -p "$out"
iverilog -g2001 -DSHARED_READBACK -s tb -o "$out/test" rtl/ngage_bram.v rtl/ngage_upp_peripherals.v rtl/ngage_mmc_host.v rtl/ngage_simif.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v rtl/ngage_keypad.v tests/phone/register_ram/reference_timers.v tests/phone/register_ram/reference_icu.v tests/phone/register_ram/tb.v > "$out/build.log" 2>&1
vvp "$out/test" > "$out/run.log" 2>&1
cat "$out/run.log"
