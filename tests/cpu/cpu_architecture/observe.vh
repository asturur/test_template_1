`define ac dut.u_zap.u_zap_core
`define au `ac.u_zap_issue_main
`define aw `ac.u_zap_writeback
integer arch_hold, arch_shift, arch_dep, arch_empty, arch_use;
integer arch_bus, arch_offer, arch_ack, arch_redirect, arch_decredirect;
integer arch_archstores;
reg [63:0] arch_rhash, arch_whash;
integer arch_transit[0:4], arch_transits[0:4];
integer arch_last_retire;
reg [31:0] arch_last_pc;
// In the FbsCli scan these known Thumb ranges also cover the BX whose
// output flags may already carry the next instruction set.
wire arch_fbs = payload_base==32'h10000000 &&
    ((retire_pc>=32'h5055d2ac && retire_pc<=32'h5055d2d0) ||
     (retire_pc>=32'h5055d3b8 && retire_pc<=32'h5055d3da));
wire [31:0] arch_rpc=retire_pc+((arch_fbs || `aw.i_flags[5]) ? 32'd4 : 32'd0);

function automatic [31:0] arch_active_bytes(input [31:0] data,input [3:0] lanes);
    integer i;
    for(i=0;i<4;i++) arch_active_bytes[i*8+:8]=lanes[i]?data[i*8+:8]:8'b0;
endfunction
task arch_begin;
    integer i;
    begin
        arch_hold=0; arch_shift=0; arch_dep=0; arch_empty=0; arch_use=0;
        arch_bus=0; arch_offer=0; arch_ack=0; arch_redirect=0; arch_decredirect=0;
        arch_last_retire=-1; arch_last_pc=0; arch_archstores=0;
        arch_rhash=64'hcbf29ce484222325; arch_whash=64'hcbf29ce484222325;
        for(i=0;i<5;i++) begin arch_transit[i]=0; arch_transits[i]=0; end
    end
endtask
task arch_sample;
    integer kind;
    begin
        if(start_cycle>=0) begin
            if(`ac.data_stall) arch_hold++;
            else if(`ac.stall_from_shifter) arch_shift++;
            else if(`au.operand_valid && `au.lock) arch_dep++;
            else if(!`au.operand_valid) arch_empty++;
            else arch_use++;
            if((cyc&&stb&&!ack)||line_active) arch_bus++;
            if(`ac.completion_offer) arch_offer++;
            if(`ac.completion_offer && `ac.i_data_wb_ack) begin
                arch_ack++;
                if(`ac.o_data_wb_we) begin
                    arch_archstores++;
                    arch_whash=(arch_whash ^ {32'b0,`ac.o_data_wb_adr}) * 64'h100000001b3;
                    arch_whash=(arch_whash ^ {28'b0,`ac.o_data_wb_sel,
                        arch_active_bytes(`ac.o_data_wb_dat,`ac.o_data_wb_sel)}) * 64'h100000001b3;
                end
            end
            if(`ac.clear_from_alu && !`ac.data_stall) arch_redirect++;
            if(`ac.clear_from_decode && !`ac.data_stall) arch_decredirect++;
            if(retire) begin
                if((arch_rpc>=payload_base && arch_rpc<payload_base+32'h100000) ||
                   (arch_rpc>=32'h50550000 && arch_rpc<32'h50561000))
                    arch_rhash=(arch_rhash ^ {32'b0,arch_rpc}) * 64'h100000001b3;
                if (arch_last_retire>=0) begin
                    kind=0;
                    if (arch_last_pc==32'h1001dce0 || arch_last_pc==32'h1001dce8) kind=1;
                    if (arch_last_pc==32'h10035020 || arch_last_pc==32'h10035030) kind=2;
                    if (arch_last_pc==32'h5055d2d4 || arch_last_pc==32'h5055d3de) kind=3;
                    if (arch_last_pc==32'h1001dcf4) kind=4;
                    arch_transit[kind]+=cycles-arch_last_retire;
                    arch_transits[kind]++;
                end
                arch_last_pc=arch_rpc; arch_last_retire=cycles;
            end
            if(trace_mode!=0 && windows==2 && cycles-start_cycle<12000) begin
                if(`ac.completion_offer)
                    $display("ARCH_DATA t=%0d pc=%08h va=%08h we=%0d ack=%0d",
                        cycles-start_cycle,
                        (`ac.data_select_p1 ? `ac.postalu1_pc_plus_8_ff : `ac.postalu_pc_plus_8_ff)-
                        ((`ac.data_select_p1 ? `ac.postalu1_flags_ff[5] : `ac.postalu_flags_ff[5])?32'd4:32'd8),
                        `ac.o_data_wb_adr,`ac.o_data_wb_we,`ac.i_data_wb_ack);
                if (retire || `au.operand_pop || `ac.alu_dav_ff || `ac.clear_from_alu)
                    $display("ARCH_EDGE t=%0d pop=%0d ipc=%08h alu=%0d apc=%08h ret=%0d rpc=%08h stall=%0d clear=%0d target=%08h fvalid=%0d fpc=%08h",
                        cycles-start_cycle,`au.operand_pop,`au.operand_pc_ff,
                        `ac.alu_dav_ff,`ac.alu_pc_plus_8_ff-(`ac.alu_flags_ff[5]?32'd4:32'd8),
                        retire,arch_rpc,`ac.data_stall,`ac.clear_from_alu,`ac.pc_from_alu,
                        `ac.fetch_valid,`ac.fetch_pc_plus_8_ff-8);
            end
        end
    end
endtask
task arch_end;
    integer i;
    begin
        $display("ARCH_WINDOW index=%0d hold=%0d shift=%0d dep=%0d empty=%0d other=%0d ext=%0d offers=%0d ack=%0d redirect=%0d decode_redirect=%0d",
            windows,arch_hold,arch_shift,arch_dep,arch_empty,arch_use,arch_bus,arch_offer,arch_ack,
            arch_redirect,arch_decredirect);
        $display("ARCH_EFFECT index=%0d pc=%016h stores=%016h count=%0d",
            windows,arch_rhash,arch_whash,arch_archstores);
        for(i=0;i<5;i++) $display("ARCH_TRANSIT index=%0d kind=%0d clocks=%0d count=%0d",
            windows,i,arch_transit[i],arch_transits[i]);
    end
endtask
`undef aw
`undef au
`undef ac
