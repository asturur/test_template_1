module tb;
reg [31:0] address,raw,expected;reg array_read,code_flash;wire [31:0] result;
ngage_flash_read_decode dut(address,raw,array_read,code_flash,result);
integer f,ret,count=0;
initial begin
 f=$fopen("build/sim/unit-flash-decode/vectors.txt","r");if(!f)$fatal(1,"missing vectors");
 while(!$feof(f)) begin
  ret=$fscanf(f,"%h %h %h %h %h\n",address,raw,array_read,code_flash,expected);
  if(ret==5) begin #1;if(result!==expected)$fatal(1,"address %h result %h expected %h",address,result,expected);count=count+1;end
 end
 if(count<500) $fatal(1,"incomplete vectors");
 $display("PASS flash dual descrambler %0d vectors",count);$finish;
end
endmodule
