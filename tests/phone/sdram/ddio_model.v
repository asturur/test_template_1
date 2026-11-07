// Ideal clock-forwarding-only ALTDDIO_OUT substitute. The production wrapper
// ties the data inputs to constants. This tests edge polarity and wiring,
// not Intel's implementation, PLL lock, IO delay or fitted timing.
// Never include this file in the Quartus source list.
module altddio_out #(
    parameter extend_oe_disable="OFF", intended_device_family="Cyclone V",
    invert_output="OFF", lpm_hint="UNUSED", lpm_type="altddio_out",
    oe_reg="UNREGISTERED", power_up_high="OFF", width=1
)(input wire [width-1:0] datain_h,datain_l,
  input wire outclock,aclr,aset,oe,outclocken,sclr,sset,
  output wire [width-1:0] dataout);
    wire [width-1:0] level=outclock ? datain_h : datain_l;
    assign dataout=aclr ? {width{1'b0}} : aset ? {width{1'b1}} :
                   (oe && outclocken) ? level : {width{1'bz}};
endmodule
