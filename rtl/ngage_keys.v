// MiSTer PS/2 events and joystick levels to the diagnostic 26-key map.
module ngage_keys(input wire clk,input wire reset,input wire inhibit,input wire [10:0] ps2_key,input wire [31:0] joystick,output wire [26:0] keys);
 reg [26:0] held=0;reg toggle=0,lshift=0,rshift=0,star_chord=0,hash_chord=0,star_pad=0,hash_pad=0;reg [4:0] index;reg valid;
 always @* begin
  valid=1;index=0;
  if(ps2_key[8])case(ps2_key[7:0])
   8'h75:index=0;8'h72:index=1;8'h6b:index=2;8'h74:index=3;8'h4a:index=11;default:valid=0;
  endcase else case(ps2_key[7:0])
   8'h5a:index=4;8'h05:index=5;8'h0d:index=6;8'h66:index=7;8'h06:index=9;
   8'h7c:index=10;8'h4a:index=11;8'h16:index=12;8'h1e:index=13;8'h26:index=14;
   8'h25:index=15;8'h2e:index=16;8'h36:index=17;8'h3d:index=18;8'h3e:index=19;8'h46:index=20;
   8'h09:index=26;8'h12:index=21;8'h59:index=21;8'h45:index=22;8'h1c:index=4;8'h76:index=24;8'h21:index=25;default:valid=0;
  endcase
 end
 always @(posedge clk)begin
  if(reset || inhibit)begin held<=0;toggle<=ps2_key[10];lshift<=0;rshift<=0;star_chord<=0;hash_chord<=0;star_pad<=0;hash_pad<=0;end
  else if(ps2_key[10]!=toggle)begin
   toggle<=ps2_key[10];
   if(valid)begin
    if(!ps2_key[8] && ps2_key[7:0]==8'h12)begin lshift<=ps2_key[9];held[21]<=ps2_key[9] || rshift;end
    else if(!ps2_key[8] && ps2_key[7:0]==8'h59)begin rshift<=ps2_key[9];held[21]<=ps2_key[9] || lshift;end
    else if(ps2_key[7:0]==8'h4a)hash_pad<=ps2_key[9];
    else if(!ps2_key[8] && ps2_key[7:0]==8'h7c)star_pad<=ps2_key[9];
    else if(!ps2_key[8] && ps2_key[7:0]==8'h26)begin
     if(ps2_key[9])begin hash_chord<=lshift || rshift;held[14]<=!(lshift || rshift);end
     else begin hash_chord<=0;held[14]<=0;end
    end else if(!ps2_key[8] && ps2_key[7:0]==8'h3e)begin
     if(ps2_key[9])begin star_chord<=lshift || rshift;held[19]<=!(lshift || rshift);end
     else begin star_chord<=0;held[19]<=0;end
    end else held[index]<=ps2_key[9];
   end
  end
 end
 wire [26:0] joy_keys;
 assign joy_keys={2'b0,(joystick[6] || joystick[11]),joystick[10],13'b0,joystick[9],1'b0,joystick[5],joystick[7],joystick[8],joystick[4],joystick[0],joystick[1],joystick[2],joystick[3]};
 wire [26:0] chord_keys={15'b0,(hash_chord || hash_pad),(star_chord || star_pad),10'b0};
 assign keys=inhibit ? 27'b0 : held | joy_keys | chord_keys;
endmodule
