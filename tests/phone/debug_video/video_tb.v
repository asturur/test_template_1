`timescale 1ns/1ps
module tb;
 reg clk=0,diagnostic=1,ce=1,hs=1,vs=1,hb=0,vb=0;
 reg [8:0] x=0,y=0;reg [11:0] rgb=12'habc;reg [767:0] values=0;
 reg [98:0] panic={3'b111,32'h00010003,32'h6f697470,32'h65637845};
 wire co,ho,vo,hbo,vbo;wire [11:0] out;
 integer xx,yy,i,fd;reg [11:0] held;
 always #5 clk=~clk;
 ngage_debug_video dut(clk,diagnostic,values,panic,x,y,ce,hs,vs,hb,vb,rgb,co,ho,vo,hbo,vbo,out);
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 initial begin
  for(i=0;i<24;i=i+1)values[i*32+:32]=32'h12345678+i;
  values[16*32+:32]=32'h08000000;values[20*32+:32]=2;
  values[21*32+:32]=32'h3f;values[22*32+:32]=32'h21;
  fd=$fopen("build/sim/unit-debug-video/screen.ppm","wb");$fwrite(fd,"P6\n320 240\n255\n");
  for(yy=0;yy<262;yy=yy+1)for(xx=0;xx<400;xx=xx+1)begin
   x=xx;y=yy;hb=xx>=320;vb=yy>=240;hs=!(xx>=336 && xx<368);vs=!(yy>=244 && yy<247);
   tick();
   if(co!==ce || ho!==hs || vo!==vs || hbo!==hb || vbo!==vb)$fatal(1,"control pipeline alignment");
   if(xx<320 && yy<240)$fwrite(fd,"%c%c%c",{out[11:8],out[11:8]},{out[7:4],out[7:4]},{out[3:0],out[3:0]});
   else if(out!==0)$fatal(1,"blanking pixels");
  end
  $fclose(fd);
  // Mid-frame source changes cannot tear an already sampled field.
  values=0;panic=0;x=0;y=10;tick();if(dut.snapshot[31:0]!==32'h12345678)$fatal(1,"frame snapshot tore");
  if(dut.panic_snapshot!=={3'b111,32'h00010003,32'h6f697470,32'h65637845})$fatal(1,"panic snapshot tore");
  // Exactly sixteen frame boundaries refresh the coherent observation packet.
  for(i=1;i<=16;i=i+1)begin
   x=0;y=0;tick();x=1;tick();
   if(i<16 && dut.snapshot[31:0]!==32'h12345678)$fatal(1,"early snapshot refresh");
  end
  if(dut.panic_snapshot!==0)$fatal(1,"panic snapshot never refreshed");
  if(dut.snapshot!==0)$fatal(1,"snapshot never refreshed");
  // Phone mode retains every input pixel and control signal with one clock delay.
  diagnostic=0;
  for(i=0;i<32;i=i+1)begin
   rgb=i*101;ce=i[0];hs=i[1];vs=i[2];hb=i[3];vb=i[4];tick();
   if(out!==rgb || co!==ce || ho!==hs || vo!==vs || hbo!==hb || vbo!==vb)$fatal(1,"phone bypass changed pixels/control");
   held=out;rgb=~rgb;#1;if(out!==held)$fatal(1,"phone RGB bypass was not registered");rgb=~rgb;
  end
  $display("PASS diagnostic text raster, stable snapshot, blanking and phone video pipeline");$finish;
 end
endmodule
