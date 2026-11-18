`define cor dut.u_zap.u_zap_core
`define alu `cor.u_zap_alu_main
reg [31:0] observed_bx;
initial if (!$value$plusargs("observed_bx=%h",observed_bx))
    $fatal(1,"directed BX PC missing");
always @(posedge clk) if(!reset && !`cor.data_stall && !`cor.clear_from_writeback &&
    !`cor.clear_from_alu && `alu.i_pc_ff==observed_bx && `alu.i_switch_ff && `alu.o_dav_nxt)
    $display("INTERWORK pc=%08h predicted=%08h taken=%0d target=%08h flush=%0d",
        observed_bx,`alu.i_ppc_ff,`alu.i_taken_ff,`alu.tmp_sum,`alu.w_clear_from_alu!=0);
`undef cor
`undef alu
