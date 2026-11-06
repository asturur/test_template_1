// N430 Nokia LRB-2 Bluetooth component boundary (schematic sheet A-17).
// GPP vector order is {GPP7,GPP6,GPP1,GPP0}; separate input/output-enable
// ports represent bidirectional pins without internal FPGA tri-states.
// Protocol and pin directions are not established. The unimplemented model
// drives no line and produces no HCI response.
module ngage_lrb2(
 input wire resetx,sleepx,sysclk,slpclk,
 input wire cbusclk,cenx,cbusdata_i,
 output wire cbusdata_o,cbusdata_oe,
 input wire [3:0] gpp_i,output wire [3:0] gpp_o,gpp_oe,
 output wire model_implemented
);
 assign cbusdata_o=1'b0;assign cbusdata_oe=1'b0;
 assign gpp_o=4'b0;assign gpp_oe=4'b0;assign model_implemented=1'b0;
endmodule
