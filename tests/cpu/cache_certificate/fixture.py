"""Extend existing independent memory oracle with a twelve-line working set."""
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[3]
s=(root/'tests/cpu/cache_resident/test.v').read_text()
s=s.replace('module test;', 'module test;\n  parameter EXPECTED_REUSE=0;\n  integer reused=0;')
marker='    $display(\n        "PASS:'
assert s.count(marker)==1
extra='''
    // Populate the bank before learning reuse facts: no refill can revoke a
    // partially learned working set in the scored sequence.
    for (j=0;j<12;j=j+1) begin
      access(0,1,32'h6000+256*j,0,4'hf,0);
      if (result !== mem[(32'h6000+256*j)>>2]) $fatal(1,"certificate fill data");
    end
    for (j=0;j<8;j=j+1) begin
      access(0,1,32'h6000+256*j,0,4'hf,1);
      if (result !== mem[(32'h6000+256*j)>>2]) $fatal(1,"certificate learn data");
    end
    for (j=0;j<8;j=j+1) begin
      access(0,1,32'h6000+256*j+4,0,4'hf,1);
      if (result !== mem[(32'h6000+256*j+4)>>2]) $fatal(1,"certificate slot data");
      if (latency==fast_read) reused=reused+1;
    end
    if (reused!=EXPECTED_REUSE) $fatal(1,"certificate reuse count %0d expected %0d",reused,EXPECTED_REUSE);
    // Exceed capacity, mutate every line and read in reverse order. Values are
    // independent of the implementation's slot/way selection and replacement.
    for (j=0;j<12;j=j+1) access(1,0,32'h6000+256*j+4*(j%8),32'h4d000000|j,4'hf,0);
    for (j=11;j>=0;j=j-1) begin
      access(0,1,32'h6000+256*j+4*(j%8),0,4'hf,1);
      if (result !== (32'h4d000000|j)) $fatal(1,"certificate replaced/mutated line data");
    end
    inv=1;tick();inv=0;tick();
    if (dut.line_result_valid!==0) $fatal(1,"certificate invalidation retained a fact");
    $display("PASS certificate working-set: 12 lines, 8 learned/revisited, reuse=%0d; wrap, stores, reverse reads and revoke",reused);
'''
s=s.replace(marker,extra+marker)
Path(sys.argv[1]).write_text(s)
