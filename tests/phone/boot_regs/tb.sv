module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,req=0,commit=0,we=0;reg [31:0] addr=0,din=0;reg [3:0] sel=15;wire claim,bad;wire [31:0] dout;
ngage_boot_regs dut(clk,reset,req,commit,we,addr,din,sel,claim,bad,dout);
task tick;begin @(posedge clk);#1;end endtask
initial begin
 tick();reset=0;@(negedge clk);req=1;we=0;addr='h08000000;#1;if(!claim||!bad)$fatal(1,"unwritten boot read");
 addr='h08000040;#1;if(!claim||bad||dout!==0)$fatal(1,"zero boot register");
 addr='h0c004748;#1;if(!claim||!bad)$fatal(1,"unwritten scratch read");
 we=1;sel=3;din='h0000abcd;commit=0;tick();we=0;#1;if(!bad)$fatal(1,"uncommitted write");
 we=1;commit=1;tick();we=0;commit=0;#1;if(bad||dout[15:0]!==16'habcd)$fatal(1,"scratch halfword");
 sel=15;#1;if(!bad)$fatal(1,"unwritten scratch upper half");
 we=1;din='h12345678;commit=1;tick();we=0;commit=0;#1;if(bad||dout!=='h12345678)$fatal(1,"scratch word");
 addr='h0c0047fc;#1;if(claim)$fatal(1,"scratch boundary");
 addr='h0c120018;sel=15;we=0;#1;if(!claim||!bad)$fatal(1,"unwritten clock latch");
 we=1;din='h76543210;commit=1;tick();we=0;commit=0;#1;if(bad||dout!=='h76543210)$fatal(1,"clock latch round trip");
 addr='h0c120034;#1;if(!bad)$fatal(1,"clock latches alias");
 $display("PASS boot latches and executable scratch validity");$finish;
end
endmodule
