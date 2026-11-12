#!/bin/sh
# Run inside the existing jotego/simulator:arm64 image. Legacy source copies
# are deliberately isolated: never restore them over the working tree.
set -eu
out=${SDRAM_LATENCY_OUT:-build/sim/unit-sdram-latency}
legacy=${SDRAM_LEGACY_DIR:-scratch/sdram-specialize-20261112/before}
mkdir -p "$out"
for version in legacy native; do
 if [ "$version" = legacy ]; then
  native=0
  owner_define=''
  sources="$legacy/ngage_sdram_adapter.v $legacy/ngage_dma_ram_mux.v $legacy/jtframe_sdram64.v $legacy/jtframe_sdram64_bank.v $legacy/jtframe_sdram64_init.v"
 else
  native=1
  owner_define='-DSDRAM_SHARED_PAYLOAD'
  sources='rtl/ngage_sdram_adapter.v rtl/ngage_dma_ram_mux.v rtl/sdram/jtframe_sdram64.v rtl/sdram/jtframe_sdram64_bank.v rtl/sdram/jtframe_sdram64_init.v'
 fi
 for hz in 78000000 104000000; do
  iverilog -g2012 $owner_define -s latency_tb -Platency_tb.NATIVE="$native" -Platency_tb.SYS_CLK_HZ="$hz" \
   -o "$out/$version-$hz" $sources rtl/ngage_sdram_clock.v tests/phone/sdram/ddio_model.v \
   rtl/ngage_sdram_arbiter.v rtl/sdram/jtframe_sdram64_latch.v rtl/sdram/jtframe_sdram64_rfsh.v \
   scratch/sdram-reference/mt48lc16m16a2.v tests/phone/sdram/latency_tb.sv
  if ! vvp "$out/$version-$hz" > "$out/$version-$hz.log" 2>&1; then
   cat "$out/$version-$hz.log";exit 1
  fi
  if grep -Ei 'error|fatal|warning|violation' "$out/$version-$hz.log"; then exit 1; fi
  grep '^PASS' "$out/$version-$hz.log"
 done
done
