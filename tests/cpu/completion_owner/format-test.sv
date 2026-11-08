// SPDX-License-Identifier: GPL-3.0-or-later
module test;
logic clk=0,reset=0,clear=0,stall=0,load=0;
logic [1:0] address=0;
logic [3:0] kinds=0;
logic [31:0] data=0,store=0;
wire [31:0] result;
logic [31:0] expected=0;
logic [31:0] rng=32'h95a67321;
integer checks=0;
zap_memory_main dut(.i_clk(clk),.i_reset(reset),.i_clear_from_writeback(clear),.i_data_stall(stall),
 .i_mem_load_ff(load),.i_mem_address_ff(address),.i_mem_rd_data(data),.i_mem_srcdest_value_ff(store),
 .i_sbyte_ff(kinds[0]),.i_ubyte_ff(kinds[1]),.i_shalf_ff(kinds[2]),.i_uhalf_ff(kinds[3]),
 .i_und_ff(1'b0),.i_fiq_ff(1'b0),.i_irq_ff(1'b0),.i_swi_ff(1'b0),.i_instr_abort_ff(1'b0),
 .i_dav_ff(1'b0),.i_mem_fault(2'd0),.o_mem_rd_data(result));
function automatic [31:0] random_word();
 rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);return rng;
endfunction
function automatic [31:0] oracle;
 logic [31:0] shifted;
 logic [7:0] byte_value;
 logic [15:0] half_value;
 byte_value=8'(data>>(8*address));half_value=16'(data>>(16*address[1]));
 if(!load)return store;
 if(kinds[1])return {24'd0,byte_value};
 if(kinds[0])return {{24{byte_value[7]}},byte_value};
 if(kinds[2])return {{16{half_value[15]}},half_value};
 if(kinds[3])return {16'd0,half_value};
 shifted=(data>>(8*address)) | (data<<(32-8*address));
 return shifted;
endfunction
initial begin
 for(integer iteration=0;iteration<64;iteration++)for(integer shape=0;shape<128;shape++)begin
  {load,address,kinds}=7'(shape);data=random_word();store=random_word();
  stall=iteration%7==0;reset=iteration%19==0;clear=iteration%13==0;
  #1;if(!stall)expected=oracle();clk=1;#1;clk=0;
  if(checks!=0 && result!==expected)$fatal(1,"registered load formatter shape=%0d iteration=%0d got=%h expected=%h",shape,iteration,result,expected);
  checks++;
 end
 $display("PASS: registered memory formatter %0d clocks, all widths/sign/rotation/priority/store/hold cases",checks);$finish;
end
endmodule
