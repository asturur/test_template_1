module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,cyc=0,stb=0,we=0,commit=0;reg [31:0] addr=0,din=0;reg [3:0] sel=15;
wire claim,ready,bad,irq,fiq,init_done;wire [31:0] dout;
ngage_board dut(.clk(clk),.rst(reset),.init_rst(reset),.cyc(cyc),.stb(stb),.we(we),.commit(commit),.adr(addr),.din(din),.sel(sel),
 .cfg_lcd(1'b1),.cfg_keypad(1'b1),.cfg_clocks(1'b1),.claim(claim),.ready(ready),.unmodeled(bad),.dout(dout),.irq(irq),.fiq(fiq),.init_done(init_done));
defparam dut.cbus.ALARM_TICKS=8;
defparam dut.cbus.ALARM_INTERVAL=1;
defparam dut.nos_timer.TICK_DIV=2;
defparam dut.mdi.ANNOUNCE_TICKS=3;
task tick;begin @(posedge clk);#1;end endtask
task wr(input [31:0] a,input [31:0] d);begin @(negedge clk);cyc=1;stb=1;we=1;addr=a;din=d;commit=1;#1;if(!claim||!ready||bad)$fatal(1,"bad board write %h",a);tick();@(negedge clk);cyc=0;stb=0;commit=0;end endtask
task halfwrite(input [31:0] a,input [15:0] v,input [3:0] lanes);begin
 @(negedge clk);cyc=1;stb=1;we=1;addr=a;sel=lanes;din=lanes==12?{v,16'b0}:{16'b0,v};commit=1;#1;
 if(!claim||!ready||bad)$fatal(1,"CBUS board write %h",a);tick();@(negedge clk);cyc=0;stb=0;commit=0;sel=15;
end endtask
task ram_read(input [31:0] a,input [31:0] expected);
 integer n;begin @(negedge clk);cyc=1;stb=1;we=0;addr=a;commit=0;n=0;#1;while(!ready && n<10)begin tick();n=n+1;end
 if(!ready||!claim||bad||dout!==expected)$fatal(1,"RAM read %h got %h expected %h",a,dout,expected);
 @(negedge clk);commit=1;tick();@(negedge clk);cyc=0;stb=0;commit=0;end
endtask
task read_eq(input [31:0] a,input [31:0] expected);begin @(negedge clk);cyc=1;stb=1;we=0;addr=a;#1;if(!claim||!ready||bad||dout!==expected)$fatal(1,"board read %h got %h",a,dout);@(negedge clk);cyc=0;stb=0;end endtask
initial begin
 tick();reset=0;wait(init_done);tick();
 wr('h0c120034,32'h12345678);read_eq('h0c120034,32'h12345678);
 if(dut.aux_ram.lane[0].mem[12'h440]!==0)$fatal(1,"boot latch also wrote GPIO backing RAM");
 read_eq('h08000040,0);wr('h08000000,32'h76543210);read_eq('h08000000,32'h76543210);wr('h0c004748,32'h1234abcd);read_eq('h0c004748,32'h1234abcd);
 ram_read('h0c030220,0);ram_read('h0c100220,0);ram_read('h0c150220,0);ram_read('h0c14f010,0);
 wr('h0c030220,32'h11223344);wr('h0c100220,32'h55667788);wr('h0c150220,32'h99aabbcc);wr('h0c14f010,32'h12345678);
 ram_read('h0c030220,32'h11223344);ram_read('h0c100220,32'h55667788);ram_read('h0c150220,32'h99aabbcc);ram_read('h0c14f010,32'h12345678);
 wr('h0d000220,32'hcafe1122);wr('h0d010220,32'hbabe3344);
 read_eq('h0d000220,32'hcafe1122);read_eq('h0d010220,32'hbabe3344);
 wr('h0c120108,2);wr('h0c120a30,4);wr('h0c120a24,1);repeat(5)tick();
 if(!irq || fiq)$fatal(1,"unit1 IRQ routing");read_eq('h0c120114,2);wr('h0c12010c,2);repeat(2)tick();if(irq)$fatal(1,"unit1 ack");
 wr('h0c1201c8,8);wr('h0c120a64,2);repeat(130)tick();if(!fiq||irq)$fatal(1,"unit60 FIQ routing");read_eq('h0c1201d0,8);read_eq('h0c1201d4,4);
 wr('h0c120a68,0);if(fiq)$fatal(1,"FIQ not cleared");
 wr('h0c120108,32'h02000000);wr('h0c150010,32'h10000000);if(!irq)$fatal(1,"NOS IRQ routing");
 read_eq('h0c120114,26);wr('h0c150010,32'h00001000);if(irq)$fatal(1,"NOS IRQ clear");
 wr('h0c120108,2);halfwrite('h0c150420,15,3);halfwrite('h0c150420,'h36,12);halfwrite('h0c150424,'hfff7,12);repeat(9)tick();
 if(!irq)$fatal(1,"CBUS alarm IRQ routing");read_eq('h0c120114,2);wr('h0c12010c,2);repeat(2)tick();if(irq)$fatal(1,"CBUS IRQ clear");
 wr('h0c1201cc,8);wr('h0c120108,32'h02000000);wr('h0c150010,32'h06000000);
 wr('h0c14b004,32'h00000500);wr('h0c1003e8,2);wr('h0c1003ec,0);
 wr('h0c120a04,2);wr('h0c120a18,32'h000632ea);repeat(20)tick();
 read_eq('h0c1003e8,32'h00020002);read_eq('h0c1001f4,32'h7cd00000);read_eq('h0c1001f8,32'h04000001);
 if(!irq)$fatal(1,"MDI status did not reach ICU");read_eq('h0c120114,26);
 wr('h0c150100,32'h00000600);if(irq)$fatal(1,"MDI status clear");
 halfwrite('h0c150420,7,3);halfwrite('h0c150420,'h2a,12);halfwrite('h0c150424,8,12);
 halfwrite('h0c150420,7,3);halfwrite('h0c150420,'h3b,12);halfwrite('h0c150424,'h400,12);
 halfwrite('h0c150200,5,12);read_eq('h0c150208,32'h000a0000);
 halfwrite('h0c150204,1,3);read_eq('h0c150208,32'h00080000);
 @(negedge clk);cyc=1;stb=1;we=1;addr='h0c150500;sel=5;din=32'hffffffff;commit=1;#1;if(!claim||!bad)$fatal(1,"invalid GPIO lanes accepted");tick();
 @(negedge clk);cyc=0;stb=0;commit=0;sel=15;ram_read('h0c150500,0);
 @(negedge clk);cyc=1;stb=1;we=1;addr='h0c1201c8;sel=3;din=8;commit=0;#1;if(!claim||!bad)$fatal(1,"bad width not identified");
 $display("PASS board ICU/timer IRQ and FIQ routing");$finish;
end
endmodule
