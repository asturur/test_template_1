// Simulation-only passive observer. Define BP_CORE as the actual zap_core path.
// Sample on the RF write edge, before NBA updates: fault context is pre-abort.
// No forces, guest writes, architectural changes, or synthesized debug ports.
`define BP_WB `BP_CORE.u_zap_writeback
`define BP_RF `BP_WB.u_zap_register_file
reg [31:0] bp_r0_pc[0:15];
reg [31:0] bp_r0_data[0:15];
reg [1:0] bp_r0_kind[0:15];
reg [31:0] bp_mem_pc[0:31];
reg [31:0] bp_mem_addr[0:31];
reg [31:0] bp_mem_data[0:31];
reg [1:0] bp_mem_fault[0:31];
reg bp_mem_load[0:31];
integer bp_mem_count = 0;
integer bp_r0_count = 0;
integer bp_faults = 0;
integer bp_j;
integer bp_index;
reg [31:0] bp_last_pc = 0;
reg [31:0] bp_last_value = 0;
reg [31:0] bp_fault_pc = 0;
reg [31:0] bp_fault_lr = 0;
reg [31:0] bp_fault_r0 = 0;
reg [31:0] bp_fault_cpsr = 0;
reg [31:0] bp_fault_producer_pc = 0;
reg [31:0] bp_fault_producer_value = 0;
reg [31:0] bp_fault_fsr = 0;
reg [31:0] bp_fault_far = 0;
wire [31:0] bp_current_pc = `BP_CORE.memory_pc_plus_8_ff -
    (`BP_CORE.memory_flags_ff[5] ? 32'd4 : 32'd8);
function [5:0] bp_lr_index;
    input [4:0] mode;
    begin
        case (mode)
            5'h11: bp_lr_index = 24;
            5'h12: bp_lr_index = 26;
            5'h13: bp_lr_index = 28;
            5'h17: bp_lr_index = 32;
            5'h1b: bp_lr_index = 30;
            default: bp_lr_index = 14;
        endcase
    end
endfunction
always @(posedge clk) begin
    if (reset) begin
        bp_r0_count = 0;
        bp_mem_count = 0;
        bp_faults = 0;
    end else begin
        // Read the same actual RF storage the CPU uses, including mode banking.
        if (`BP_CORE.memory_data_abt_ff == 2'b01 && bp_current_pc == 32'h503ad63c) begin
            bp_faults = bp_faults + 1;
            bp_fault_pc = bp_current_pc;
            bp_fault_producer_pc = bp_last_pc;
            bp_fault_producer_value = bp_last_value;
            bp_fault_lr = `BP_RF.mem[bp_lr_index(`BP_WB.cpsr_ff[4:0])];
            bp_fault_r0 = `BP_RF.mem[0];
            bp_fault_cpsr = `BP_WB.cpsr_ff;
            bp_fault_fsr = `BP_CORE.u_zap_cp15_cb.r[5];
            bp_fault_far = `BP_CORE.u_zap_cp15_cb.r[6];
            $display("BAD_POINTER pc=%08x r0=%08x lr=%08x cpsr=%08x fsr=%08x far=%08x last_r0_pc=%08x last_r0_value=%08x", bp_fault_pc, bp_fault_r0, bp_fault_lr, bp_fault_cpsr, bp_fault_fsr, bp_fault_far, bp_last_pc, bp_last_value);
            for (bp_j = 0; bp_j < 40; bp_j = bp_j + 1)
                $display("FAULT_RF index=%0d value=%08x", bp_j, `BP_RF.mem[bp_j]);
            for (bp_j = (bp_mem_count > 32 ? bp_mem_count - 32 : 0); bp_j < bp_mem_count; bp_j = bp_j + 1) begin
                bp_index = bp_j % 32;
                $display("MEM_HISTORY pc=%08x va=%08x data=%08x load=%0d fault=%0d", bp_mem_pc[bp_index], bp_mem_addr[bp_index], bp_mem_data[bp_index], bp_mem_load[bp_index], bp_mem_fault[bp_index]);
            end
            for (bp_j = (bp_r0_count > 16 ? bp_r0_count - 16 : 0); bp_j < bp_r0_count; bp_j = bp_j + 1) begin
                bp_index = bp_j % 16;
                $display("R0_HISTORY pc=%08x value=%08x kind=%0d", bp_r0_pc[bp_index], bp_r0_data[bp_index], bp_r0_kind[bp_index]);
            end
            $finish; // Fresh diagnostic run: save on the first Count abort.
        end
        // Capture only completed owned P2 transactions, before pipeline advance.
        // Data is the returned word for loads, outgoing data for stores.
        if (`BP_CORE.completion_valid && `BP_CORE.postalu_request_cyc && `BP_CORE.postalu_request_stb) begin
            bp_index = bp_mem_count % 32;
            bp_mem_pc[bp_index] = `BP_CORE.postalu_pc_plus_8_ff -
                (`BP_CORE.postalu_flags_ff[5] ? 32'd4 : 32'd8);
            bp_mem_addr[bp_index] = `BP_CORE.postalu_address_ff;
            bp_mem_data[bp_index] = `BP_CORE.postalu_mem_load_ff ?
                `BP_CORE.completion_data : `BP_CORE.o_data_wb_dat;
            bp_mem_load[bp_index] = `BP_CORE.postalu_mem_load_ff;
            bp_mem_fault[bp_index] = `BP_CORE.completion_fault;
            bp_mem_count = bp_mem_count + 1;
        end
        // Mirror actual write priority: background C > memory B > arithmetic A.
        // kind 0: arithmetic, 1: regular load, 2: background load, 3: async CP15.
        // The last two have no trustworthy instruction PC on this write port.
        if (`BP_RF.i_wr_addr_c[0] || (`BP_RF.i_wen && (`BP_RF.i_wr_addr_a == 0 || `BP_RF.i_wr_addr_b == 0))) begin
            bp_index = bp_r0_count % 16;
            bp_r0_pc[bp_index] = bp_current_pc;
            bp_r0_kind[bp_index] = 0;
            bp_r0_data[bp_index] = `BP_RF.i_wr_data_a;
            if (`BP_RF.i_wr_addr_b == 0) begin
                bp_r0_kind[bp_index] = 1;
                bp_r0_data[bp_index] = `BP_RF.i_wr_data_b;
            end
            if (`BP_WB.i_copro_reg_en) begin
                bp_r0_pc[bp_index] = 0;
                bp_r0_kind[bp_index] = 3;
            end
            if (`BP_RF.i_wr_addr_c[0]) begin
                bp_r0_pc[bp_index] = 0;
                bp_r0_kind[bp_index] = 2;
                bp_r0_data[bp_index] = `BP_RF.i_wr_data_c;
            end
            bp_last_pc = bp_r0_pc[bp_index];
            bp_last_value = bp_r0_data[bp_index];
            bp_r0_count = bp_r0_count + 1;
        end
    end
end
`undef BP_RF
`undef BP_WB
