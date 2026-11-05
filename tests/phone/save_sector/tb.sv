module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,start=0,load=0;reg [13:0] index=0;
wire ready,done,error,mv,mw;wire [31:0] ma,md,lba;wire [3:0] mb;reg m_done=0;reg [31:0] m_rdata=0;
wire rd,wr;reg ack=0;reg [12:0] ha=0;reg [15:0] hd=0;reg hwe=0;wire [15:0] hout;
reg [31:0] ram[0:255];reg [15:0] disk[0:255];integer i;
ngage_save_sector_bridge #(.C_SECTORS(1),.PMM_SECTORS(1),.SD_TIMEOUT(5000)) dut(clk,reset,start,load,index,ready,done,error,mv,1'b1,mw,ma,md,mb,m_done,m_rdata,lba,rd,wr,ack,ha,hd,hwe,hout);
always @(posedge clk)begin
 m_done<=0;if(mv)begin
  if(ma>=32'h31400000 && ma<32'h31400200)begin m_rdata<=ram[(ma-32'h31400000)>>2];if(mw)ram[(ma-32'h31400000)>>2]<=md;end
  else if(ma>=32'h31800000 && ma<32'h31800200)begin m_rdata<=ram[128+((ma-32'h31800000)>>2)];if(mw)ram[128+((ma-32'h31800000)>>2)]<=md;end
  else $fatal(1,"bad DDR address %h",ma);
  m_done<=1;
 end
end
task tick;begin @(posedge clk);#1;end endtask
task launch(input bit op,input [13:0] s);begin @(negedge clk);start=1;load=op;index=s;tick();@(negedge clk);start=0;end endtask
initial begin
 for(i=0;i<256;i=i+1)begin ram[i]=32'h12340000+i;disk[i]=0;end
 tick();reset=0;tick();launch(0,0);wait(wr);if(lba!=1)$fatal(1,"C lba");@(negedge clk);ack=1;
 for(i=0;i<256;i=i+1)begin ha=i;#1;disk[i]=hout;@(negedge clk);end
 ack=0;wait(done);if(error)$fatal(1,"save failure");tick();
 for(i=0;i<128;i=i+1)ram[i]=0;
 launch(1,0);wait(rd);@(negedge clk);ack=1;
 for(i=0;i<256;i=i+1)begin ha=i;hd=disk[i];hwe=1;tick();@(negedge clk);end
 hwe=0;ack=0;wait(done);if(error)$fatal(1,"load failure");
 for(i=0;i<128;i=i+1)if(ram[i]!==32'h12340000+i)$fatal(1,"round trip word %d got %h",i,ram[i]);
 tick();launch(0,1);wait(wr);if(lba!=2)$fatal(1,"PMM lba");@(negedge clk);ack=1;tick();@(negedge clk);ack=0;wait(done);
 tick();launch(0,2);wait(done);if(!error)$fatal(1,"out of range accepted");
 $display("PASS DDR to HPS sector snapshot and reload");$finish;
end
initial begin #2000000;$fatal(1,"timeout");end
endmodule
