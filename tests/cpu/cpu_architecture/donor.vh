`define dc dut.u_zap.g_arm9.u_arm9_core
localparam [31:0] payload_base=32'h10000000;
integer trace_mode=0, dstores;
reg [63:0] drhash,dwhash;

function automatic [31:0] active_bytes(input [31:0] data,input [3:0] lanes);
    integer i;
    for(i=0;i<4;i++) active_bytes[i*8+:8]=lanes[i]?data[i*8+:8]:8'b0;
endfunction

task donor_begin;
    begin
        dstores=0;
        drhash=64'hcbf29ce484222325;
        dwhash=64'hcbf29ce484222325;
    end
endtask

task donor_sample;
    begin
        if(start_cycle>=0) begin
            if(retire && ((retire_pc>=payload_base && retire_pc<payload_base+32'h100000) ||
               (retire_pc>=32'h50550000 && retire_pc<32'h50561000)))
                drhash=(drhash ^ {32'b0,retire_pc}) * 64'h100000001b3;
            if(dut.dbg_d_done && dut.dbg_d_we) begin
                dstores++;
                dwhash=(dwhash ^ {32'b0,dut.dbg_d_va[31:2],2'b0}) * 64'h100000001b3;
                dwhash=(dwhash ^ {28'b0,dut.dbg_d_sel,
                    active_bytes(dut.dbg_d_wdata,dut.dbg_d_sel)}) * 64'h100000001b3;
            end
            if(trace_mode!=0 && windows==2 && (trace_mode==2 || cycles-start_cycle<12000)) begin
                if(`dc.o_data_wb_cyc)
                    $display("DONOR_DATA t=%0d pc=%08h va=%08h we=%0d ack=%0d fast=%0d",
                        cycles-start_cycle,(`dc.data_pc8-(`dc.data_pc8>=32'h50500000 && `dc.data_pc8<32'h50600000 ? 32'd4:32'd8)),`dc.o_data_wb_adr,
                        `dc.o_data_wb_we,`dc.i_data_wb_ack,`dc.i_data_ack_fast);
                if(retire || `dc.a_a_valid || `dc.a_redirect)
                    $display("DONOR_EDGE t=%0d alu=%0d apc=%08h ret=%0d rpc=%08h stall=%0d clear=%0d target=%08h fet=%0d fpc=%08h",
                        cycles-start_cycle,`dc.a_a_valid && `dc.a_a_can_finish,`dc.a_pc,
                        retire,retire_pc,!`dc.backend_ready,`dc.a_redirect,`dc.a_redirect_target,
                        `dc.o_instr_wb_cyc && `dc.i_instr_wb_ack,`dc.o_instr_wb_adr);
            end
        end
    end
endtask

task donor_end;
    $display("DONOR_EFFECT index=%0d pc=%016h stores=%016h count=%0d",windows,drhash,dwhash,dstores);
endtask
`undef dc
