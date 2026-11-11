module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,req=0,commit=0,we=0;reg [31:0] addr=0,din=0;reg [3:0] sel=15;
reg [95:0] ip=0,fp=0;wire claim,bad,irq,fiq;wire [31:0] dout;wire [95:0] clear;
integer bank_index, source_index, other_index;
reg [31:0] bank_base;
ngage_icu dut(clk,reset,req,commit,we,addr,din,sel,ip,fp,claim,bad,dout,irq,fiq,clear,1'b0);
task tick;begin @(posedge clk);#1;end endtask
task wr(input [31:0] a,input [31:0] d);begin @(negedge clk);req=1;we=1;commit=1;addr=a;din=d;#1;if(!claim||bad)$fatal(1,"write decode %h",a);tick();@(negedge clk);req=0;commit=0;end endtask
task read_eq(input [31:0] a,input [31:0] d);begin @(negedge clk);req=1;we=0;addr=a;#1;if(!claim||bad||dout!==d)$fatal(1,"read %h got %h expected %h",a,dout,d);@(negedge clk);req=0;end endtask
initial begin
 tick();reset=0;ip[0]=1;ip[1]=1;ip[7]=1;ip[25]=1;fp[3]=1;fp[26]=1;tick();if(irq||fiq)$fatal(1,"masked input delivered");
 read_eq('h0c1201d0,32'h04000008);read_eq('h0c1201d4,4);
 wr('h0c120108,32'h02000082);if(!irq)$fatal(1,"IRQ mask");read_eq('h0c120114,2);read_eq('h0c120110,32'h80);
 wr('h0c120108,1);read_eq('h0c120114,1);
 @(negedge clk);req=1;we=1;commit=0;addr='h0c12010c;din=3;tick();if(clear!==0)$fatal(1,"uncommitted clear");
 commit=1;tick();if(clear[1:0]!==2'b11)$fatal(1,"clear pulse");@(negedge clk);req=0;commit=0;tick();read_eq('h0c120114,8);
 wr('h0c1201c8,32'h04000008);if(!fiq)$fatal(1,"FIQ mask");wr('h0c1201cc,8);if(!fiq)$fatal(1,"FIQ masked wrong source");wr('h0c1201cc,32'h04000000);if(fiq)$fatal(1,"FIQ did not mask");
 @(negedge clk);req=1;we=1;commit=1;addr='h0c120108;sel=3;din=1;#1;if(!bad)$fatal(1,"partial width accepted");tick();@(negedge clk);req=0;commit=0;sel=15;
 read_eq('h0c120108,32'h02000080);
 // Exercise the full current-register width, including one-based source 32,
 // simultaneous MMC-range sources and independent masks in all three banks.
 for (bank_index = 0; bank_index < 3; bank_index = bank_index + 1) begin
  bank_base = 32'h0c120100 + 64 * bank_index;
  ip = 0;
  wr(bank_base + 12, 32'hffffffff);
  ip[bank_index*32+:32] = 32'hffffffff;
  read_eq(bank_base + 20, 0);
  if (irq) $fatal(1, "masked bank %0d asserted IRQ", bank_index);
  wr(bank_base + 8, 32'hffffffff);
  read_eq(bank_base + 20, 1);
  for (source_index = 0; source_index < 32; source_index = source_index + 1) begin
   for (other_index = source_index; other_index < 32; other_index = other_index + 1) begin
    ip[bank_index*32+:32] = (32'd1 << source_index) | (32'd1 << other_index);
    read_eq(bank_base + 20, source_index + 1);
   end
  end
  if (!irq || fiq) $fatal(1, "IRQ bank crossed into FIQ plane");
  wr(bank_base + 12, 32'h80000000);
  read_eq(bank_base + 20, 0);
  if (irq) $fatal(1, "clear left bank %0d asserted", bank_index);
 end
 $display("PASS ICU priority, masks, FIQ and committed clears");
 $display("PASS ICU all 96 sources and 1584 within-bank priority pairs");
 $finish;
end
endmodule
