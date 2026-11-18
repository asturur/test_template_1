// Donor fetch selects the next launch in F1, where the BTB lookup returns.
`define C dut.u_zap.g_arm9.u_arm9_core
`define D `C.u_front_decode
`define F `D.u_fetch
task fill_frontend_sample;
    begin
        if (trace_mode != 0 && windows == 2 && start_cycle >= 0)
            $display("FRONT_DONOR t=%0d launch=%08h advance=%0d f1=%08h f1_valid=%0d treq=%08h req=%0d ack=%0d pred=%0d target=%08h redirect=%0d retry=%0d push=%0d pop=%0d count=%0d head=%08h d_valid=%0d decode=%08h backend_ready=%0d fast=%0d",
                cycles-start_cycle, `F.launch_pc, `F.advance, `F.f1[31:0], `F.f1[35],
                `F.o_address, `F.o_request, `F.i_ack, `F.predicted, `F.prediction[42:11],
                `F.i_redirect, `F.retry, `F.push, `F.pop, `F.count, `F.o_pc,
                `C.d_valid, `C.d_pc, `C.backend_ready, `C.i_data_ack_fast);
    end
endtask
`undef F
`undef D
`undef C
