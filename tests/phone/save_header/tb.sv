module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,start=0;reg [1:0] profile=1;reg [255:0] core,ext;wire [7:0] addr;reg [15:0] mem[0:255];wire busy,done,valid;
reg [15:0] word_q;
ngage_save_header dut(clk,reset,start,profile,core,ext,addr,word_q,busy,done,valid);
always @(posedge clk) word_q <= mem[addr];
task tick;begin @(posedge clk);#1;end endtask
task run;begin @(negedge clk);start=1;tick();@(negedge clk);start=0;wait(done);#1;end endtask
integer i;
initial begin
 for(i=0;i<32;i=i+1)begin core[i*8+:8]=i;ext[i*8+:8]=i+32;end
 $readmemh("build/sim/unit-save-header/header.hex",mem);
 tick();reset=0;run();if(!valid)$fatal(1,"valid header rejected");
 mem[20]=mem[20]^1;run();if(valid)$fatal(1,"corrupt header accepted");
 mem[20]=mem[20]^1;profile=2;run();if(valid)$fatal(1,"wrong profile accepted");
 profile=1;ext[0]=!ext[0];run();if(valid)$fatal(1,"wrong firmware accepted");
 ext[0]=!ext[0];profile=0;run();if(!valid)$fatal(1,"service pair rejected profile 1");
 $readmemh("build/sim/unit-save-header/header2.hex",mem);
 run();if(!valid)$fatal(1,"service pair rejected profile 2");
 profile=1;run();if(valid)$fatal(1,"legacy profile accepted mismatched profile 2");
 profile=0;$readmemh("build/sim/unit-save-header/header3.hex",mem);
 run();if(valid)$fatal(1,"service pair accepted unknown seed profile");
 $display("PASS save header legacy/service profiles, hashes and CRC");$finish;
end
endmodule
