module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,lock=0,cr=0,cw=0,dr=0,dw=0,ma=0;
reg [24:0] ca=25'h100,da=25'h200;reg [31:0] cd=32'h1111,dd=32'h2222,mrd=32'h1234;reg [3:0] cb=15,db=15;
wire cak,dak,mreq,mwe;wire [31:0] crd,drd,md;wire [24:0] addr;wire [3:0] mbe;
integer grant;
ngage_sdram_arbiter dut(clk,reset,lock,cr,cw,ca,cd,cb,cak,crd,dr,dw,da,dd,db,dak,drd,mreq,mwe,addr,md,mbe,ma,mrd,,);
task tick;begin @(posedge clk);#1;end endtask
initial begin
 tick();reset=0;@(negedge clk);lock=1;dr=1;repeat(3) tick();if(mreq) $fatal(1,"DMA passed lock gap");
 @(negedge clk);cr=1;tick();if(!mreq || addr!=ca) $fatal(1,"CPU not selected");
 @(negedge clk);ma=1;#1;if(!cak || dak) $fatal(1,"CPU response wrong");tick();
 @(negedge clk);ma=0;cr=0;tick();tick();if(mreq) $fatal(1,"DMA passed locked gap");
 @(negedge clk);cr=1;cw=1;tick();if(!mreq || !mwe) $fatal(1,"second CPU beat missing");
 @(negedge clk);ma=1;#1;if(!cak || dak) $fatal(1,"write response wrong");tick();
 @(negedge clk);ma=0;cr=0;lock=0;tick();tick();if(!mreq || addr!=da) $fatal(1,"DMA starved after unlock");
 @(negedge clk);ma=1;#1;if(!dak || cak || drd!=mrd) $fatal(1,"DMA response wrong");tick();
 @(negedge clk);ma=0;dr=0;tick();tick();if(mreq) $fatal(1,"duplicate transaction");
 $display("PASS SDRAM CPU/DMA arbitration and SWP lock");

 // Both clients keep offering work. A grant must retain its own address,
 // direction, data and lanes while the peer delays acknowledgement.
 @(negedge clk);
 reset=1;
 tick();
 @(negedge clk);
 reset=0; cr=1; dr=1; cw=0; dw=1; da=25'h240; dd=32'h12345678; db=4'b0101;
 for (grant = 0; grant < 32; grant = grant + 1) begin
  tick();
  if (!mreq || addr !== (grant[0] ? da : ca) || mwe !== grant[0])
   $fatal(1, "wrong grant %0d", grant);
  if (grant[0] && (md !== dd || mbe !== db)) $fatal(1, "DMA write payload lost");
  @(negedge clk);
  if (grant[0]) begin da=da+4; dd=~dd; db=~db; end
  else ca=ca+4;
  repeat (3) tick();
  if (!mreq || addr !== (grant[0] ? da-25'd4 : ca-25'd4) || mwe !== grant[0])
   $fatal(1, "live request changed owned fields");
  if (grant[0] && (md !== ~dd || mbe !== ~db)) $fatal(1, "live write changed captured payload");
  @(negedge clk); ma=1;
  #1;
  if (cak !== !grant[0] || dak !== grant[0]) $fatal(1, "completion leaked to the wrong client");
  tick();
  @(negedge clk); ma=0;
 end

 // Warm reset cancels client ownership, even if completion arrives on its
 // assertion edge. The backing adapter separately drains physical commands.
 cr=0;
 tick();
 if (!mreq || !mwe) $fatal(1, "DMA reset fixture did not acquire write");
 @(negedge clk); reset=1; ma=1;
 #1;
 if (cak || dak) $fatal(1, "completion escaped warm reset");
 tick();
 @(negedge clk); reset=0; ma=0; dr=0;
 tick();
 if (mreq || cak || dak) $fatal(1, "canceled DMA transfer replayed");
 $display("PASS SDRAM 32 alternating CPU/DMA grants, captured writes and reset cancellation");
 $finish;
end
endmodule
