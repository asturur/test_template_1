`timescale 1ns/1ps
// Check the actual CE/DE stream, not a host crop of a padded screenshot.
module tb;
reg clk=0,reset=1,diagnostic=0,wv=0,dv=0,full=0;reg [31:0] wa=0,wd=0,dd=0;reg [14:0] da=0;
wire ce,hb,vb,hs,vs,complete,unsupported;wire [11:0] rgb;
integer i,x,y,pattern=0,active,hticks,vticks,total,fd;reg begun;reg [1023:0] picture_path,hex_path;
reg [31:0] picture[0:18303];reg replay=0;
always #5 clk=~clk;
ngage_lcd_display dut(.clk(clk),.reset(reset),.diagnostic(diagnostic),.status(8'h80),.save_state(3'b0),.write_valid(wv),.write_addr(wa),.write_data(wd),.dma_valid(dv),.dma_frame_full(full),.dma_word_addr(da),.dma_data(dd),.ce_pix(ce),.hsync(hs),.vsync(vs),.hblank(hb),.vblank(vb),.rgb(rgb),.frame_complete(complete),.unsupported(unsupported));
function [11:0] expected;
 input integer xx,yy;
 reg [31:0] pair;
 begin
  if(replay)begin pair=picture[(yy*176+xx)/2];expected=xx%2 ? pair[27:16] : pair[11:0];end
  else if(pattern==0)expected=(xx<<4)|(yy&15);
  else expected=(yy<<4)|(xx&15);
 end
endfunction
task wr;input [31:0] a,d;begin @(negedge clk);wv=1;wa=a;wd=d;@(negedge clk);wv=0;end endtask
task capture;
 begin
  active=0;total=0;hticks=0;vticks=0;begun=0;
  begin: raster
   while(1)begin
    @(negedge clk);
    if(ce)begin
     x=dut.scan_x;y=dut.scan_y;
     if(x==0 && y==0)begin if(begun)disable raster;begun=1;end
     if(begun)begin
      total=total+1;if(!hs)hticks=hticks+1;if(!vs)vticks=vticks+1;
      if(!hb && !vb)begin
       if(x<72 || x>=248 || y<16 || y>=224)$fatal(1,"border included in phone DE %0d,%0d",x,y);
       if(rgb!==expected(x-72,y-16))$fatal(1,"pixel mismatch pattern %0d at %0d,%0d: %h want %h",pattern,x,y,rgb,expected(x-72,y-16));
       active=active+1;
       if(fd)$fwrite(fd,"%c%c%c",{rgb[11:8],rgb[11:8]},{rgb[7:4],rgb[7:4]},{rgb[3:0],rgb[3:0]});
      end
      if((hb || vb) && rgb!==0)$fatal(1,"analog padding is not black");
      if(hb!==!(x>=72 && x<248) || vb!==!(y>=16 && y<224))$fatal(1,"native blanking mismatch");
     end
    end
   end
  end
  if(active!=176*208 || total!=400*262 || hticks!=32*262 || vticks!=3*400)
   $fatal(1,"raster totals active=%0d total=%0d hs=%0d vs=%0d",active,total,hticks,vticks);
 end
endtask
initial begin
 fd=0;
 if($value$plusargs("FRAME=%s",hex_path))begin $readmemh(hex_path,picture);replay=1;end
 repeat(2)@(negedge clk);reset=0;
 // Even an unknown panel opcode must not paint a diagnostic stripe into
 // the phone's real pixels. The diagnostic/export flag remains asserted.
 wr('h0c121200,'h09200000);wr('h0c121208,'hfe);wr('h0c121208,'haf);
 for(pattern=0;pattern<(replay?1:2);pattern=pattern+1)begin
  for(i=0;i<18304;i=i+1)begin
   @(negedge clk);dv=1;da=i;x=(i%88)*2;y=i/88;
   dd={4'b0,expected(x+1,y),4'b0,expected(x,y)};
  end
  @(negedge clk);dv=0;if(!complete || !unsupported)$fatal(1,"frame/diagnostic flags");
  if(replay && $value$plusargs("PPM=%s",picture_path))begin fd=$fopen(picture_path,"wb");if(!fd)$fatal(1,"open PPM");$fwrite(fd,"P6\n176 208\n255\n");end
  capture();if(fd)begin $fclose(fd);fd=0;end
 end
 // Diagnostic page retains its own 320x240 active area.
 diagnostic=1;
 @(negedge clk);dut.scan_x=319;dut.scan_y=239;#1;if(hb || vb)$fatal(1,"diagnostic active area shrank");
 dut.scan_x=320;dut.scan_y=240;#1;if(!hb || !vb)$fatal(1,"diagnostic blanking");
 $display("PASS native 176x208 CE/DE pixels, sync, diagnostics and zero baked-in borders");$finish;
end
initial begin #150000000;$fatal(1,"native raster timeout");end
endmodule
