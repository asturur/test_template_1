`timescale 1ns/1ps
module test;
 logic clk=0;always #5 clk=~clk;
 logic reset=1,iv=0,ready=0;logic [7:0] ib=0;wire ir,ov;wire [7:0] ob;
 ngage_bt_hci_stub dut(.clk(clk),.reset(reset),.rx_valid(iv),.rx_byte(ib),.rx_ready(ir),.tx_valid(ov),.tx_byte(ob),.tx_ready(ready));
 task automatic tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task automatic send(input logic [7:0] b);begin if(!ir)$fatal(1,"input not ready");ib=b;iv=1;tick();iv=0;end endtask
 task automatic command(input logic [15:0] op,input logic [7:0] len);begin send(1);send(0);send(op[7:0]);send(op[15:8]);send(len);end endtask
 task automatic expect_byte(input logic [7:0] b);begin
  if(!ov || ob!==b)$fatal(1,"response mismatch got %h expected %h",ob,b);
  tick();if(!ov || ob!==b)$fatal(1,"output changed under backpressure");ready=1;tick();ready=0;
 end endtask
 initial begin #100000;$fatal(1,"timeout");end
 initial begin
  tick();reset=0;tick();
  command(16'h1005,0);
  expect_byte(4);expect_byte(0);expect_byte(8'h0e);expect_byte(11);expect_byte(1);expect_byte(5);expect_byte(8'h10);expect_byte(0);
  expect_byte(8'h53);expect_byte(1);expect_byte(8'h40);expect_byte(8);expect_byte(0);expect_byte(1);expect_byte(0);
  if(ov || !ir)$fatal(1,"response did not end");
  command(16'h1234,2);send(8'haa);send(8'hbb);
  expect_byte(4);expect_byte(0);expect_byte(8'h0e);expect_byte(4);expect_byte(1);expect_byte(8'h34);expect_byte(8'h12);expect_byte(1);
  command(16'h0401,0);
  expect_byte(4);expect_byte(0);expect_byte(8'h0f);expect_byte(4);expect_byte(0);expect_byte(1);expect_byte(1);expect_byte(4);
  expect_byte(4);expect_byte(0);expect_byte(1);expect_byte(1);expect_byte(0);
  if(ov || !ir)$fatal(1,"inquiry did not end");
  command(16'h0c14,0);
  expect_byte(4);expect_byte(0);expect_byte(8'h0e);expect_byte(252);expect_byte(1);expect_byte(8'h14);expect_byte(8'h0c);expect_byte(0);
  expect_byte("N");expect_byte("-");expect_byte("G");expect_byte("a");expect_byte("g");expect_byte("e");
  for(integer n=6;n<248;n=n+1)expect_byte(0);
  if(ov || !ir)$fatal(1,"long response did not end");
  $display("PASS: no-radio HCI command framing, backpressure, inquiry and 248-byte name");$finish;
 end
endmodule
