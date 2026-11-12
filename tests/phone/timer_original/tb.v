`timescale 1ns/1ps
module tb;
parameter integer DIV=4;
reg clk=0,reset=1;always #5 clk=~clk;
wire cyc,stb,we;wire [31:0] address,value,data,pc;wire [3:0] lanes;
reg [31:0] program_words[0:2047],app_words[0:180223],boot_words[0:191],ram[0:32767];
integer cycles=0,delay=0,wait_cycles=0,i,checked=0,mmio=0;
wire access=cyc&&stb;
wire timer_ready;
wire ack=access&&delay>=wait_cycles&&(!timer||timer_ready);
wire app=address>=32'h50320000&&address<32'h503d0000;
wire boot=address>=32'h3000&&address<32'h3300;
wire kernel_ram=address>=32'h80000000&&address<32'h80020000;
wire timer=address>=32'h58120a00&&address<32'h58120ac0;
wire icu=address==32'h58120108;
wire claim,bad,p0,p1,p3,periodic;wire [31:0] timer_data;wire [5:0] pending;
assign data=address<8192?program_words[address[12:2]]:
 app?app_words[(address-32'h50320000)>>2]:boot?boot_words[(address-32'h3000)>>2]:
 kernel_ram?ram[address[16:2]]:timer?timer_data:0;
ngage_cpu cpu(.clk(clk),.reset(reset),.irq(1'b0),.fiq(1'b0),
 .wb_cyc(cyc),.wb_stb(stb),.wb_write(we),.wb_address(address),.wb_write_data(value),
 .wb_byte_enable(lanes),.wb_ack(ack),.wb_read_data(data),.wb_error(1'b0),.debug_pc(pc));
ngage_timers #(.CLOCK_DIV(DIV)) dut(.clk(clk),.reset(reset),.req(access&&timer),
 .commit(ack&&timer),.we(we),.addr(address-32'h4c000000),.din(value),.sel(lanes),
 .clear_unit1(1'b0),.claim(claim),.bad(bad),.dout(timer_data),.timer0_pending(p0),
 .unit1_pending(p1),.unit60_pending(p3),.timer0_rearm(),.periodic_active(periodic),
 .sysc74_seen(1'b0),.pending_sources(pending),.ready(timer_ready));
always @(posedge clk)if(!reset)begin
 cycles<=cycles+1;
 if(cycles>200000)$fatal(1,"timeout pc=%h checked%0d",pc,checked);
 if(access&&!ack)delay<=delay+1;else delay<=0;
 if(ack)begin
  if(timer)begin
   if(!claim||bad)$fatal(1,"timer access rejected %h",address);mmio<=mmio+1;
  end
  if(we&&kernel_ram)for(i=0;i<4;i=i+1)if(lanes[i])ram[address[16:2]][8*i+:8]<=value[8*i+:8];
  if(we&&address==32'he0000000)begin
   if(value!=checked+1)$fatal(1,"phase order");checked<=checked+1;
   case(value)
    1: if(dut.g_timer[0].control!=2||dut.g_timer[0].reload!=18200000||
          dut.g_timer[0].count<18199000||p0)$fatal(1,"original boot init");
    2: if(p0||ram[4]!=11||ram[32'h1040>>2]!=1||!periodic)$fatal(1,"original tick ISR");
    3: if(p1||dut.g_timer[1].running||dut.g_timer[1].count!=0)$fatal(1,"original highres ISR");
    4: if(dut.g_timer[1].running||dut.g_timer[1].count==0)$fatal(1,"original stop");
    5: if(!pending[2]||dut.g_timer[2].count!=0)$fatal(1,"original delay");
    6: if(dut.g_timer[2].running||dut.g_timer[2].count!=0)$fatal(1,"second original timer2 delay returned before expiry count=%0d",dut.g_timer[2].count);
    7: if(p3||!dut.g_timer[3].running||dut.g_timer[3].reload!=390)$fatal(1,"original medint rearm");
   endcase
  end
  if(we&&address==32'hf0000000)begin
   if(value!=32'h50415353||checked!=7)$fatal(1,"ARM reported %h phase%0d",value,checked);
   $display("PASS original NEM4 timer instructions DIV=%0d waits=%0d phases=%0d mmio=%0d cycles=%0d",DIV,wait_cycles,checked,mmio,cycles);$finish;
  end
  if(!(address<8192||app||boot||kernel_ram||timer||icu||
       address==32'he0000000||address==32'hf0000000))$fatal(1,"unmapped %h PC%h",address,pc);
 end
end
initial begin
 for(i=0;i<2048;i=i+1)program_words[i]=0;
 for(i=0;i<32768;i=i+1)ram[i]=0;
 $readmemh("scratch/ngage2-integration/timer-flow-2026-11-11/original/program.hex",program_words);
 $readmemh("scratch/ngage2-integration/timer-flow-2026-11-11/original/app.hex",app_words);
 $readmemh("scratch/ngage2-integration/timer-flow-2026-11-11/original/boot.hex",boot_words);
 if($value$plusargs("wait=%d",wait_cycles))begin end
 repeat(4)@(negedge clk);reset=0;
end
endmodule
