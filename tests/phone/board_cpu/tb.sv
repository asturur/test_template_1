`timescale 1ns/1ps
module tb;
reg clk=0,cold=1,reset=1;always #5 clk=~clk;
wire cyc,stb,we,lock,ack,err;wire [31:0] addr,wdata,rdata;wire [3:0] sel;wire [2:0] ct;wire [1:0] bt;
wire claim,ready,bad,irq,fiq,init_done;wire [31:0] board_data;reg [31:0] rom[0:1023];integer cycles=0;
ngage_cpu cpu(.clk(clk),.reset(reset),.irq(irq),.fiq(fiq),.wb_lock(lock),.wb_cyc(cyc),.wb_stb(stb),.wb_address(addr),.wb_write(we),.wb_write_data(wdata),.wb_byte_enable(sel),.wb_cycle_type(ct),.wb_burst_type(bt),.wb_ack(ack),.wb_read_data(rdata),.wb_error(err));
ngage_board board(.clk(clk),.rst(reset),.init_rst(cold),.cyc(cyc),.stb(stb),.adr(addr),.we(we),.din(wdata),.sel(sel),.commit(ack&&claim),.cfg_lcd(1'b1),.cfg_keypad(1'b1),.cfg_clocks(1'b1),.claim(claim),.ready(ready),.dout(board_data),.unmodeled(bad),.irq(irq),.fiq(fiq),.init_done(init_done));
assign ack=cyc && stb && (claim ? (ready && !bad) : 1'b1);
reg invalid_response=0;
always @(posedge clk)begin if(reset)invalid_response<=0;else invalid_response<=!invalid_response && cyc && stb && claim && ready && bad;end
assign err=invalid_response;
assign rdata=claim ? board_data : (addr<4096 ? rom[addr[11:2]] : 0);
always @(posedge clk)if(!reset)begin
 cycles<=cycles+1;
 if(cycles>100000)$fatal(1,"CPU IRQ/FIQ timeout irq=%b fiq=%b",irq,fiq);

 if(ack && we && addr==32'hf0000000)begin if(wdata!=32'h50415353)$fatal(1,"CPU failure %h",wdata);$display("PASS ARM CPU IRQ/FIQ and invalid-register data abort");$finish;end
end
initial begin
 for(integer i=0;i<1024;i=i+1)rom[i]=0;
 $readmemh("build/sim/unit-board-cpu/program.hex",rom);
 repeat(5)@(negedge clk);cold=0;wait(init_done);repeat(2)@(negedge clk);reset=0;
end
endmodule
