`define TC dut.u_zap.u_zap_core
`define TI `TC.u_zap_issue_main
integer thumb_p1[0:1], thumb_late[0:1];
integer thumb_hint, thumb_pickup, thumb_fault_pickup, thumb_hold, thumb_retry;
reg held_thumb_owner;
reg [31:0] held_thumb_pc, held_thumb_address;

task thumb_begin;
    begin
        thumb_p1[0]=0; thumb_p1[1]=0;
        thumb_late[0]=0; thumb_late[1]=0;
        thumb_hint=0; thumb_pickup=0; thumb_fault_pickup=0;
        thumb_hold=0; thumb_retry=0;
    end
endtask

task thumb_sample;
    reg thumb_offer;
    reg [31:0] producer;
    reg journal;
    begin
        thumb_offer=`TC.completion_offer && `TC.p1_load_start && `TC.postalu1_flags_ff[5];
        producer=(`TC.data_select_p1 ? `TC.postalu1_pc_plus_8_ff : `TC.postalu_pc_plus_8_ff)-8;
        journal=trace_mode!=0 && windows==2 && start_cycle>=0 && payload_base==32'h50500000;
        if (start_cycle>=0) begin
            if (`TC.lookup_alu_hint && `TC.alu_flags_ff[5]) thumb_hint++;
            if (thumb_offer) thumb_p1[`TC.postalu1_pc_plus_8_ff[1]]++;
            if (`TI.operand_pop && `TI.late_eligible && `TC.postalu1_flags_ff[5]) begin
                thumb_late[`TI.operand_pc_plus_8_ff[1]]++;
                if (journal) $display("THUMB_ACCEPT t=%0d pc=%08h producer=%08h",
                    cycles-start_cycle,`TI.operand_pc_plus_8_ff-8,`TC.postalu1_pc_plus_8_ff-8);
            end
            if (!`TC.data_stall && !`TC.stall_from_shifter && !`TC.clear_from_writeback &&
                !`TC.clear_from_alu && (`TC.issue_late_rn || `TC.issue_late_rm) &&
                `TC.postalu_flags_ff[5]) begin
                if (`TC.completion_fault==0) thumb_pickup++;
                else thumb_fault_pickup++;
                if (journal) $display("THUMB_PICKUP t=%0d pc=%08h fault=%0d",
                    cycles-start_cycle,`TC.issue_pc_plus_8_ff-8,`TC.completion_fault);
            end
            if (held_thumb_owner) begin
                if (`TC.completion_offer && `TC.i_data_wb_ack) thumb_retry++;
                else if (!`TC.clear_from_writeback) thumb_hold++;
            end
            if (journal && `TC.alu_dav_ff && `TC.alu_flags_ff[5] && !`TC.data_stall &&
                !`TC.clear_from_writeback)
                $display("THUMB_EXEC t=%0d pc=%08h",cycles-start_cycle,`TC.alu_pc_plus_8_ff-8);
            if (journal && retire)
                $display("THUMB_RET t=%0d pc=%08h",cycles-start_cycle,retire_pc);
        end
        if (held_thumb_owner && !`TC.clear_from_writeback &&
            (!`TC.completion_offer || producer!=held_thumb_pc ||
             `TC.o_data_wb_adr!=held_thumb_address))
            $fatal(1,"Thumb early demand changed during retry");
        held_thumb_owner=(held_thumb_owner || thumb_offer) &&
                         `TC.completion_offer && !`TC.i_data_wb_ack && !`TC.clear_from_writeback;
        if (held_thumb_owner) begin
            held_thumb_pc=producer;
            held_thumb_address=`TC.o_data_wb_adr;
        end
    end
endtask

task thumb_end;
    $display("THUMB_WINDOW index=%0d p1_low=%0d p1_high=%0d hint=%0d use_low=%0d use_high=%0d pickup=%0d fault_pickup=%0d hold=%0d retry=%0d",
        windows,thumb_p1[0],thumb_p1[1],thumb_hint,thumb_late[0],thumb_late[1],
        thumb_pickup,thumb_fault_pickup,thumb_hold,thumb_retry);
endtask
`undef TI
`undef TC
