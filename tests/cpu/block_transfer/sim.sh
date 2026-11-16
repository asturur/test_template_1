#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
out=${1:-build/sim/unit-block-transfer}
mkdir -p "$out"
sequence=${BLOCK_SEQUENCE_RTL:-rtl/arm/zap_predecode_uop_sequencer.sv}
decode=${BLOCK_DECODE_RTL:-rtl/arm/zap_decode.sv}
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary -j 3 --timing --assert -Wno-fatal -Wno-lint -Irtl/arm --top-module test --Mdir "$out" \
 "$sequence" "$decode" rtl/arm/zap_ones_counter.sv tests/cpu/block_transfer/test.v > "$out/build.log" 2>&1
# The imported sequencer prints an advisory for many defined base-in-list
# and PC-store encodings. Count and hash all advisories without flooding logs.
python3 - "$root" "$out" <<'PYTHON'
import hashlib,subprocess,sys
root,out=sys.argv[1:];count=0;digest=hashlib.sha256()
command=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',root+':/work','-w','/work','--entrypoint','/work/'+out+'/Vtest','jotego/simulator:arm64']
process=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
for raw in process.stdout:
 digest.update(raw)
 if b'-Info:' in raw:
  count+=1
  if count<=2:sys.stdout.buffer.write(raw)
 else:sys.stdout.buffer.write(raw)
print('SEQUENCER_ADVISORIES count=%d raw_sha256=%s'%(count,digest.hexdigest()))
sys.exit(process.wait())
PYTHON
