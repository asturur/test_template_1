`timescale 1ns/1ps
module tb;
reg clk=0,reset=1,mount=0,ro=0,start=0,ack=0;reg [63:0] size=1024;reg [12:0] ha=0;
wire mounted,busy,error,done,freeze,rd,wr;wire [31:0] lba;wire [10:0] debug_word;wire [15:0] debug_data=16'h5000 | debug_word;wire [15:0] hd;
integer i,transactions=0,freezes=0;always #5 clk=~clk;
ngage_diag_export #(.TIMEOUT(1000)) dut(.clk(clk),.reset(reset),.mount(mount),.readonly_image(ro),.image_size(size),.start(start),.mounted(mounted),.busy(busy),.error(error),.done(done),.freeze_trace(freeze),.debug_word(debug_word),.debug_data(debug_data),.sd_lba(lba),.sd_rd(rd),.sd_wr(wr),.sd_ack(ack),.hps_addr(ha),.hps_dout(16'b0),.hps_we(1'b0),.hps_din(hd));
always @(posedge clk)if(freeze)freezes<=freezes+1;
task pulse_start;begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
task mount_disk;begin @(negedge clk);mount=1;@(negedge clk);mount=0;end endtask
initial begin
 repeat(2)@(negedge clk);reset=0;ro=1;mount_disk;pulse_start;if(!error || mounted)begin $display("FAIL readonly image");$finish;end
 ro=0;size=512;mount_disk;pulse_start;if(!error || mounted)begin $display("FAIL undersized image");$finish;end
 size=1024;mount_disk;if(!mounted)begin $display("FAIL writable image");$finish;end
 pulse_start;
 for(transactions=0;transactions<2;transactions=transactions+1)begin
  wait(wr);if(lba!==transactions || rd || !busy)begin $display("FAIL request LBA");$finish;end
  @(negedge clk);ack=1;
  for(i=0;i<256;i=i+1)begin ha=i;@(negedge clk);#1;if(hd!==(16'h5000 | (transactions*256+i)))begin $display("FAIL sector %0d word %0d got %h",transactions,i,hd);$finish;end @(negedge clk);end
  ack=0;@(negedge clk);
 end
 wait(done);if(error || busy || freezes!=1024)begin $display("FAIL completion freeze=%0d",freezes);$finish;end
 @(negedge clk);pulse_start;wait(wr);wait(done);if(!error || busy)begin $display("FAIL HPS timeout reporting");$finish;end
 @(negedge clk);pulse_start;if(!done || !error)begin $display("FAIL unsafe retry after HPS timeout");$finish;end
 $display("PASS diagnostic snapshot, disk validation and two-sector HPS export");$finish;
end
initial begin #100000;$display("FAIL export timeout");$finish;end
endmodule
