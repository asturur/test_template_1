// N601 Mjoelner GSM RF component boundary (schematic sheet A-22).
// Digital control pins only; analog I/Q and radio operation are not modeled.
// The register protocol and data direction have not been established.
module ngage_mjoelner(
 input wire resetx,rfbusclk,rfbusenx,rfbusda_i,
 output wire rfbusda_o,rfbusda_oe,output wire model_implemented
);
 assign rfbusda_o=1'b0;assign rfbusda_oe=1'b0;assign model_implemented=1'b0;
endmodule
