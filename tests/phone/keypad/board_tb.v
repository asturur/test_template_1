`timescale 1ns/1ps
module tb;
integer test_cycles=0;
reg clk=0,rst=1,cold=1,cyc=0,stb=0,we=0,commit=0;reg [31:0] addr=0,din=0;reg [3:0] sel=15;reg [26:0] keys=0;
integer k;reg [31:0] direct_mask;
wire init,claim,ready,bad;wire [31:0] dout;always #5 clk=~clk;
always @(posedge clk)test_cycles<=test_cycles+1;
ngage_board #(.KEYPAD_ENABLE(1)) dut(.clk(clk),.rst(rst),.init_rst(cold),.cyc(cyc),.stb(stb),.we(we),.adr(addr),.din(din),.sel(sel),.commit(commit),.keys(keys),.sim_present(1'b0),
 .cfg_lcd(1'b1),.cfg_keypad(1'b1),.cfg_clocks(1'b1),.dma_irq_pending(1'b0),.sim_fiq_pending(1'b0),.cpu_ack(1'b0),.cpu_err(1'b0),.cpu_rdata(32'b0),
 .init_done(init),.claim(claim),.ready(ready),.unmodeled(bad),.dout(dout));
task access;input [31:0] a,d;input [3:0] lanes;input wr;input [31:0] mask,expect;begin
 @(negedge clk);addr=a;din=d;sel=lanes;we=wr;cyc=1;stb=1;commit=0;while(!ready)@(negedge clk);#1;
 if(!claim || bad || (!wr && (dout&mask)!==expect))begin $display("FAIL board input addr %h got %h want %h",a,dout,expect);$finish;end
 commit=1;@(negedge clk);cyc=0;stb=0;commit=0;
end endtask
initial begin
 repeat(2)@(negedge clk);cold=0;wait(init);@(negedge clk);rst=0;
 access('h0c150400,'h1f000000,8,1,0,0);access('h0c120c14,'h00080000,15,1,0,0);
 keys[0]=1;access('h0c150208,0,12,0,'h2c060000,'h2c040000);keys[0]=0;
 access('h0c15040c,'h00010000,12,1,0,0);keys[5]=1;access('h0c150400,0,3,0,'h1f,'h1e);keys[5]=0;access('h0c150400,0,3,0,'h1f,'h1f);
 // The UEM-routed GENIO1 loopback must still work with the keypad enabled.
 // Its output-low phase was hidden by the rocker's unconditional idle pullup.
 access('h0c150420,15,3,1,0,0);access('h0c150420,'h002a0000,12,1,0,0);access('h0c150424,'h00080000,12,1,0,0);
 access('h0c150200,'h00010000,12,1,0,0);
 access('h0c150208,0,12,0,'h00020000,'h00020000);
 access('h0c150204,1,3,1,0,0);
 access('h0c150208,0,12,0,'h00020000,0);
 // A held rocker can ground the routed-high input; releasing restores it.
 access('h0c150200,'h00010000,12,1,0,0);keys[0]=1;
 access('h0c150208,0,12,0,'h00020000,0);keys[0]=0;
 access('h0c150208,0,12,0,'h00020000,'h00020000);
 access('h0c150420,15,3,1,0,0);access('h0c150420,'h002a0000,12,1,0,0);access('h0c150424,0,12,1,0,0);
 access('h0c150208,0,12,0,'h00020000,'h00020000);
 // UEM release sequence, then observe the separate PWRONX held level.
 access('h0c150420,'h0000000f,3,1,0,0);access('h0c150420,'h00360000,12,1,0,0);access('h0c150424,'hfff70000,12,1,0,0);
 access('h0c150420,7,3,1,0,0);access('h0c150420,'h01350000,12,1,0,0);access('h0c150424,0,12,0,'h00100000,0);
 keys[26]=1;access('h0c150424,0,12,0,'h00100000,'h00100000);keys[26]=0;access('h0c150424,0,12,0,'h00100000,0);
 // Replay NEM-4 op0/2/3/4 idle configuration before IRQ delivery.
 access('h0c150400,0,3,1,0,0);access('h0c15040c,0,3,1,0,0);
 access('h0c15040c,'h3f000000,8,1,0,0);
 access('h0c150400,'h001f0000,4,1,0,0);access('h0c120c14,0,15,1,0,0);
 access('h0c150410,'h3f,1,1,0,0);access('h0c150014,'h00ee0000,4,1,0,0);
 // Both keypad and NOS remain independent owners of shared source 25.
 keys=0;access('h0c150100,'h00ee0004,15,1,0,0);
 access('h0c120108,'h02000000,15,1,0,0);
 access('h0c150010,'h10000000,15,1,0,0);
 keys[5]=1;access('h0c150100,0,15,0,'h00001004,'h00001004);
 access('h0c120114,0,15,0,'hffffffff,26);
 access('h0c150100,4,1,1,0,0);
 access('h0c150100,0,15,0,'h00001004,'h00001000);
 access('h0c120114,0,15,0,'hffffffff,26);
 access('h0c150100,'h1000,3,1,0,0);
 access('h0c120114,0,15,0,'hffffffff,0);
 keys[5]=0;access('h0c150100,0,15,0,4,0);
 keys[5]=1;access('h0c150100,0,15,0,4,4);
 access('h0c120114,0,15,0,'hffffffff,26);
 // ICU masking does not acknowledge the keypad's separately latched event.
 access('h0c12010c,'h02000000,15,1,0,0);
 access('h0c120114,0,15,0,'hffffffff,0);
 access('h0c150100,0,15,0,4,4);
 access('h0c120108,'h02000000,15,1,0,0);
 access('h0c120114,0,15,0,'hffffffff,26);
 access('h0c150100,4,1,1,0,0);keys[5]=0;
 // Direct-key status shares the NOS-owned address. Upper-byte W1C must
 // reach the keypad too; unrelated byte lanes must not acknowledge it.
 keys=0;
 for(k=0;k<6;k=k+1)begin
  case(k)
   0:direct_mask='h00200000; 1:direct_mask='h00020000;
   2:direct_mask='h00080000; 3:direct_mask='h00800000;
   4:direct_mask='h00040000; 5:direct_mask='h00400000;
  endcase
  keys=27'b1<<(k==5?25:k);
  access('h0c150100,0,15,0,direct_mask,direct_mask);
  access('h0c120114,0,15,0,'hffffffff,26);
  access('h0c150100,direct_mask,1,1,0,0);
  access('h0c150100,0,15,0,direct_mask,direct_mask);
  access('h0c150100,direct_mask,4,1,0,0);
  access('h0c150100,0,15,0,direct_mask,0);
  access('h0c120114,0,15,0,'hffffffff,0);
  // Held input must not regenerate the acknowledged edge.
  access('h0c150100,0,15,0,direct_mask,0);keys=0;
 end
 $display("PASS board keypad rocker, matrix, shared W1C and UEM PWRONX cycles=%0d",test_cycles);$finish;
end
endmodule
