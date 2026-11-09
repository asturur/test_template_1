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

// Functional model of the production ALTDDIO_IN configuration. Both outputs
// update on rising edges; dataout_l carries the preceding falling-edge sample.
// Physical IO packing/delays must be checked in Quartus, not this model.
module altddio_in #(
    parameter width=1, intended_device_family="Cyclone V",
    invert_input_clocks="OFF", power_up_high="OFF",
    lpm_type="altddio_in", lpm_hint="UNUSED"
)(input wire [width-1:0] datain,
  input wire inclock,inclocken,aclr,aset,sclr,sset,
  output reg [width-1:0] dataout_h,dataout_l);
    reg [width-1:0] falling;
    initial begin
        if (invert_input_clocks != "OFF" || power_up_high != "OFF")
            $fatal(1,"Unsupported ALTDDIO_IN test configuration");
        falling = 0;
        dataout_h = 0;
        dataout_l = 0;
    end
    always @(negedge inclock or posedge aclr or posedge aset) begin
        if (aclr) falling <= 0;
        else if (aset) falling <= {width{1'b1}};
        else if (inclocken) falling <= datain;
    end
    always @(posedge inclock or posedge aclr or posedge aset) begin
        if (aclr) begin dataout_h <= 0; dataout_l <= 0; end
        else if (aset) begin
            dataout_h <= {width{1'b1}}; dataout_l <= {width{1'b1}};
        end else if (inclocken) begin
            dataout_h <= datain;
            dataout_l <= falling;
        end
    end
endmodule
