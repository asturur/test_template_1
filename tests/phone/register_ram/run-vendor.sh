#!/bin/sh
set -eu
model=${1:?pass existing altera_mf.v}
out=build/sim/unit-register-ram-vendor
mkdir -p "$out"
# Keep the Intel/poison model on the passive bank, not unrelated large UPP RAMs.
python3 - <<'PYGEN'
from pathlib import Path
out=Path('build/sim/unit-register-ram-vendor')
src=Path('rtl/ngage_bram.v').read_text()
(out/'behavioral.v').write_text(src.replace('module ngage_bram #','module ngage_behavioral_bram #'))
(out/'intel.v').write_text('`define ALTERA_RESERVED_QIS\n'+src.replace('module ngage_bram #','module ngage_test_bram #')+'\n`undef ALTERA_RESERVED_QIS\n')
(out/'poison.v').write_text(Path('tests/cpu/cache_dirty_packed/poison_bram.v').read_text().replace('module ngage_bram #','module ngage_test_bram #'))
PYGEN
docker run --rm --pull=never --network none --platform linux/arm64 \
 --mount "type=bind,src=$PWD,dst=/src,readonly" \
 --mount "type=bind,src=$PWD/$out,dst=/out" \
 --mount "type=bind,src=$model,dst=/vendor/altera_mf.v,readonly" \
 --workdir /src --entrypoint sh jotego/simulator:arm64 -c '
set -eu
for profile in standalone shared; do
 extra="rtl/ngage_timers.v rtl/ngage_icu.v"
 if [ "$profile" = shared ]; then extra="-DSHARED_READBACK rtl/ngage_upp_peripherals.v rtl/ngage_mmc_host.v rtl/ngage_simif.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v rtl/ngage_keypad.v"; fi
for mode in vendor poison; do
 if [ "$mode" = vendor ]; then ram="-DALTERA_RESERVED_QIS rtl/ngage_bram.v /vendor/altera_mf.v"; else ram="tests/cpu/cache_dirty_packed/poison_bram.v"; fi
 if [ "$profile" = shared ]; then
  if [ "$mode" = vendor ]; then model=/out/intel.v; else model=/out/poison.v; fi
  # Compile the two renamed implementations separately to scope vendor defines.
  ram="/out/behavioral.v /out/selected-$mode.v tests/phone/register_ram/model_wrapper.v"
  cp "$model" /out/selected-$mode.v
  if [ "$mode" = vendor ]; then ram="$ram /vendor/altera_mf.v"; fi
 fi
 iverilog -g2001 -s tb -o /out/test-$profile-$mode $ram $extra tests/phone/register_ram/reference_timers.v tests/phone/register_ram/reference_icu.v tests/phone/register_ram/tb.v > /out/build-$profile-$mode.log 2>&1
 vvp /out/test-$profile-$mode > /out/run-$profile-$mode.log 2>&1
 cat /out/run-$profile-$mode.log
done
done'
