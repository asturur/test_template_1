module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,start=0,write_sector=0;reg [31:0] lba=0;
wire ready,done,error;reg [7:0] la=0;reg [15:0] ld=0;reg lwe=0;wire [15:0] lout;
integer i;wire [31:0] sdlba;wire rd,wr;reg ack=0;reg [12:0] ha=0;reg [15:0] hd=0;reg hwe=0;wire [15:0] hout;
ngage_sd_sector #(.TIMEOUT(300)) dut(clk,reset,start,write_sector,lba,ready,done,error,la,ld,lwe,lout,sdlba,rd,wr,ack,ha,hd,hwe,hout);
task tick;begin @(posedge clk);#1;end endtask
initial begin
 tick();reset=0;tick();
 @(negedge clk);la=9;ld=16'h1234;lwe=1;tick();@(negedge clk);lwe=0;start=1;write_sector=1;lba=42;tick();
 if(!wr||rd||sdlba!=42||ready)$fatal(1,"write request");
 @(negedge clk);start=0;ha=9;tick();#1;if(hout!=16'h1234)$fatal(1,"host read buffer");
 ack=1;tick();if(wr||rd||done)$fatal(1,"ack start");repeat(3)tick();
 @(negedge clk);ack=0;tick();if(!done||error||!ready)$fatal(1,"write completion");
 @(negedge clk);start=1;write_sector=0;lba=7;tick();if(!rd||wr)$fatal(1,"read request");
 @(negedge clk);start=0;ack=1;
 for(i=0;i<256;i=i+1)begin ha=i;hd=(i==11?16'habcd:i);hwe=1;tick();@(negedge clk);end
 hwe=0;ack=0;tick();if(!done||error)$fatal(1,"read completion status");la=11;tick();#1;if(lout!=16'habcd)$fatal(1,"read completion");
 @(negedge clk);start=1;write_sector=0;tick();@(negedge clk);start=0;ack=1;
 for(i=0;i<5;i=i+1)begin ha=i;hd=i;hwe=1;tick();@(negedge clk);end
 hwe=0;ack=0;tick();if(!done || !error || ready)$fatal(1,"short sector accepted");
 @(negedge clk);reset=1;tick();@(negedge clk);reset=0;tick();
 @(negedge clk);start=1;tick();@(negedge clk);start=0;repeat(301)tick();if(ready || rd || wr)$fatal(1,"timeout must block retries");
 @(negedge clk);reset=1;tick();@(negedge clk);reset=0;tick();
 @(negedge clk);start=1;tick();@(negedge clk);start=0;ack=1;tick();repeat(301)tick();if(ready || rd || wr)$fatal(1,"stuck ack must block retries");
 $display("PASS HPS sector request, buffer and timeout handshake");$finish;
end
endmodule
