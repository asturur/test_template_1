set -eu
ulimit -c 0
out=build/sim/upp-ddr3-impact/mixed
run() {
    profile=$1
    shift
    "$out/obj/Vtb" "$@" > "$out/$profile.log" 2>&1 || { cat "$out/$profile.log"; exit 1; }
    printf '%s\n' "$profile"
    grep -E '^(PASS|UPP_)' "$out/$profile.log"
}
run baseline-idle
run upload-idle +upp_regions=1 +upp_read_extra=48 +upp_write_extra=24
run nos-idle +upp_regions=2 +upp_read_extra=48 +upp_write_extra=24
run baseline-stress +upp_stress
run upload-8-4 +upp_stress +upp_regions=1 +upp_read_extra=8 +upp_write_extra=4
run nos-8-4 +upp_stress +upp_regions=2 +upp_read_extra=8 +upp_write_extra=4
run upload-48-24 +upp_stress +upp_regions=1 +upp_read_extra=48 +upp_write_extra=24
run nos-48-24 +upp_stress +upp_regions=2 +upp_read_extra=48 +upp_write_extra=24
run both-48-24 +upp_stress +upp_regions=3 +upp_read_extra=48 +upp_write_extra=24
