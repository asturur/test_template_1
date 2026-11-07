`timescale 1ns/1ps
module tb;
reg clk=0,reset=1,mount=0,start=0,ack=0,fault=0,tv=0;reg [12:0] ha=0;reg [31:0] ta=0,td=0;
wire mounted,busy,error,done,freeze,rd,wr;wire [31:0] lba;wire [10:0] word;wire [15:0] data,hd;integer i,part,f;
always #5 clk=~clk;
ngage_diagnostics diag(.clk(clk),.cold_reset(reset),.freeze_trace(freeze),.fault(fault),.fault_is_fetch(1'b0),.fault_address(32'h12345678),.fault_reason(3'd2),.trace_valid(tv),.trace_lost(1'b0),.trace_addr(ta),.trace_data(td),.trace_sel(4'hf),.read_word(word),.read_data(data),.fault_seen());
ngage_diag_export #(.TIMEOUT(1000)) exp(.clk(clk),.reset(reset),.mount(mount),.readonly_image(1'b0),.image_size(64'd1024),.start(start),.mounted(mounted),.busy(busy),.error(error),.done(done),.freeze_trace(freeze),.debug_word(word),.debug_data(data),.sd_lba(lba),.sd_rd(rd),.sd_wr(wr),.sd_ack(ack),.hps_addr(ha),.hps_dout(16'b0),.hps_we(1'b0),.hps_din(hd));
initial begin
 f=$fopen("build/sim/unit-diag-export/captured.ngd","wb");if(!f)begin $display("FAIL opening output");$finish;end
 repeat(2)@(negedge clk);reset=0;mount=1;@(negedge clk);mount=0;
 for(i=0;i<3;i=i+1)begin @(negedge clk);tv=1;ta='h0de00000+i*4;td='h41424340+i;end
 @(negedge clk);tv=0;fault=1;@(negedge clk);fault=0;start=1;@(negedge clk);start=0;
 wait(freeze);@(negedge clk);tv=1;repeat(2)@(negedge clk);tv=0;
 for(part=0;part<2;part=part+1)begin
  wait(wr);if(lba!==part)begin $display("FAIL LBA");$finish;end @(negedge clk);ack=1;
  for(i=0;i<256;i=i+1)begin ha=i;#1;$fwrite(f,"%c%c",hd[7:0],hd[15:8]);@(negedge clk);end
  ack=0;@(negedge clk);
 end
 wait(done);$fclose(f);if(error)begin $display("FAIL export error");$finish;end
 $display("PASS diagnostic ring to captured disk");$finish;
end
initial begin #100000;$display("FAIL timeout");$finish;end
endmodule
