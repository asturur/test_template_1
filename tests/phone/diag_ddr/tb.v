`timescale 1ns/1ps
module tb;
    parameter RING_BITS=10;
    parameter PHYSICAL=0;
    reg clk=0; always #5 clk=~clk;
    reg reset=1,cpu_reset=1,char_valid=0;
    reg [7:0] char_data=0;
    reg [767:0] values=0;
    wire capture;
    wire [10:0] debug_word;
    wire [15:0] debug_data;
    reg tv=0;reg [31:0] ta=0,td=0;
    reg [3:0] sel=1;
    wire [98:0] panic_report;
    ngage_diagnostics source(.clk(clk),.cold_reset(reset),.freeze_trace(capture),
        .save_slot_error(2'b10),.fault(1'b0),.fault_address(32'b0),.fault_is_fetch(1'b0),.fault_reason(3'b0),
        .trace_valid(tv),.trace_lost(1'b0),.trace_addr(ta),.trace_data(td),.trace_sel(sel),
        .read_word(debug_word),.read_data(debug_data),.fault_seen(),.panic_report(panic_report));
    wire sv,sr,sw,sd;wire [31:0] sa,sdata,srd;
    wire xv,xr,xw,xd;wire [31:0] xa,xdata,xrd,lost;
    ngage_diag_ddr #(.PERIOD(12000),.BUILD_TAG(64'h0032343131303100)) snapshot(
        .clk(clk),.reset(reset),.cpu_reset(cpu_reset),.save_observation(64'h12345678abcdef00),.save_queue_observation(32'h514101c2),.values(values),
        .capture_active(capture),.debug_word(debug_word),.debug_data(debug_data),
        .req_valid(sv),.req_ready(sr),.req_write(sw),.req_addr(sa),.req_data(sdata),.rsp_valid(sd),.rsp_data(srd));
    ngage_diag_text_ddr #(.RING_BITS(RING_BITS),.GAP_CYCLES(8)) text(
        .clk(clk),.reset(reset),.cpu_reset(cpu_reset),.char_valid(char_valid),.char_data(char_data),
        .cycles(values[159:128]),.dropped(lost),.req_valid(xv),.req_ready(xr),.req_write(xw),
        .req_addr(xa),.req_data(xdata),.rsp_valid(xd),.rsp_data(xrd));
    wire dv,dr,dw,dd;wire [31:0] da,ddata,drd;
    ngage_ddr_arbiter diag_arb(.clk(clk),.reset(reset),.cpu_lock(1'b0),
        .l_bulk(1'b0),.c_bulk(1'b0),.req_bulk(),.c_line(1'b0),.req_line(),
        .rsp_beat_valid(1'b0),.rsp_beat_data(64'b0),.rsp_beat_last(1'b0),.c_beat_valid(),.c_beat_data(),.c_beat_last(),
        .l_valid(sv),.l_ready(sr),.l_write(sw),.l_addr(sa),.l_data(sdata),.l_be(4'hf),.l_done(sd),.l_rdata(srd),
        .c_valid(xv),.c_ready(xr),.c_write(xw),.c_addr(xa),.c_data(xdata),.c_be(4'hf),.c_done(xd),.c_rdata(xrd),
        .req_valid(dv),.req_ready(dr),.req_write(dw),.req_addr(da),.req_data(ddata),.req_be(),.rsp_valid(dd),.rsp_data(drd));
    reg lv=0;wire lr,ld;reg [31:0] la=32'h30000100,ldata=32'h12345678;
    wire mv,mr,mw,md;wire [31:0] ma,mdata,mrd;wire [3:0] mbe;
    ngage_diag_loader_port port(.clk(clk),.reset(reset),.load_valid(lv),.load_ready(lr),
        .load_addr(la),.load_data(ldata),.load_be(4'hf),.load_done(ld),
        .diag_valid(dv),.diag_ready(dr),.diag_write(dw),.diag_addr(da),.diag_data(ddata),.diag_done(dd),.diag_rdata(drd),
        .mem_valid(mv),.mem_ready(mr),.mem_write(mw),.mem_addr(ma),.mem_data(mdata),.mem_be(mbe),.mem_done(md),.mem_rdata(mrd));
    // Shared memory returns one owned response after variable stalls.
    reg hold=0,pending=0,response=0;reg [31:0] response_data=0;
    reg [3:0] delay=0;
    reg [31:0] memory[0:16383];
    integer clocks=0,loads=0,snapshot_commits=0,text_commits=0,i,j,k,fd,base,before_seq;
    wire physical_ready, physical_done;
    wire [31:0] physical_data;
    assign mr=PHYSICAL ? physical_ready : !hold&&!pending&&!response&&(clocks%7!=1);
    assign md=PHYSICAL ? physical_done : response;
    assign mrd=PHYSICAL ? physical_data : response_data;
    reg [31:0] expected_read=0;
    reg expect_read=0;
    always @(posedge clk) begin
        if (mv&&mr) begin
            expect_read<=!mw;
            if (!mw) expected_read<=memory[(ma-32'h313f0000)>>2];
        end
        if (PHYSICAL && md && expect_read && mrd!==expected_read)
            $fatal(1,"physical DDR read lanes/address %h expected%h",mrd,expected_read);
    end
    wire [28:0] physical_addr;
    wire [63:0] physical_din;
    wire [7:0] physical_be, physical_burst;
    wire physical_rd,physical_we;
    reg [63:0] physical_dout=0;
    reg physical_return=0;
    wire physical_busy=hold || clocks%7==1;
    ngage_ddr_adapter #(.STREAM_TRANSPORT(1),.ROM_CACHE(0),.ROM_CACHE_BYTES(8192),.LINE_REFILL(1)) adapter (
        .clk(clk),.reset(reset),.req_valid(PHYSICAL&&mv),.req_ready(physical_ready),
        .req_write(mw),.req_addr(ma),.req_wdata(mdata),.req_be(mbe),
        .rsp_valid(physical_done),.rsp_data(physical_data),.req_fetch(1'b0),.req_line(1'b0),
        .rsp_beat_valid(),.rsp_beat_data(),.rsp_beat_last(),.transport_idle(),
        .ddr_addr(physical_addr),.ddr_din(physical_din),.ddr_be(physical_be),
        .ddr_rd(physical_rd),.ddr_we(physical_we),.ddr_busy(physical_busy),
        .ddr_dout(physical_dout),.ddr_dout_ready(physical_return),.ddr_burstcount(physical_burst));
    reg [63:0] physical_memory[0:8191];
    integer pi,pb;
    always @(posedge clk) begin
        physical_return<=0;
        if(PHYSICAL&&(physical_rd||physical_we)&&!physical_busy) begin
            if(physical_burst!=1)$fatal(1,"diagnostic must be scalar");
            if(physical_addr!=29'h06000020) begin
                if(physical_addr<29'h0627e000||physical_addr>=29'h06280000)
                    $fatal(1,"physical guard address %h",physical_addr);
                pi=physical_addr-29'h0627e000;
                if(physical_we) begin
                    for(pb=0;pb<8;pb=pb+1)
                        if(physical_be[pb])physical_memory[pi][pb*8+:8]<=physical_din[pb*8+:8];
                end else begin physical_dout<=physical_memory[pi];physical_return<=1;end
            end
        end
    end
    always @(posedge clk)begin
        clocks<=clocks+1;response<=0;
        if(reset)begin pending<=0;response<=0;end
        else if(mv&&mr)begin
            pending<=1;delay<=clocks%4;
            if(ma==32'h30000100)begin
                if(!mw||mdata!=32'h12345678||!lv)$fatal(1,"loader payload/owner");
                loads<=loads+1;response_data<=0;
            end else begin
                if(ma<32'h313f0000||ma>=32'h31400000||ma[1:0])$fatal(1,"out of reserved guard %h",ma);
                base=(ma-32'h313f0000)>>2;
                response_data<=memory[base];
                if(mw)begin
                    if(mbe!==15)$fatal(1,"partial diagnostic write");
                    memory[base]<=mdata;
                    if(ma>=32'h313ff000 && ma[9:0]==1020 && mdata!=0)begin
                        if(memory[(base&~255)]!==32'h3244474e || (mdata^32'h4344474e)!==memory[(base&~255)+2])
                            $fatal(1,"snapshot published before payload");
                        snapshot_commits<=snapshot_commits+1;
                    end
                    if(ma>=32'h313f0100 && ma<32'h313ff000 && ma[4:0]==28 &&mdata!=0)begin
                        if((mdata^32'h4354474e)!==memory[base-7])$fatal(1,"text seal mismatch");
                        text_commits<=text_commits+1;
                    end
                end
            end
        end else if(pending&&!hold)begin
            if(delay==0)begin response<=1;pending<=0;end else delay<=delay-1'b1;
        end
    end
    task tick;begin @(negedge clk);end endtask
    task emit;
        input integer n;
        begin for(j=0;j<n;j=j+1)begin
            @(negedge clk);char_valid=1;char_data=65+(j%26);
            @(negedge clk);char_valid=0;
        end end
    endtask
    task drain;
        begin wait(text.fill==0&&!text.pending_valid&&text.length==0&&text.state==8);repeat(4)tick();end
    endtask
    initial begin
        for(i=0;i<16384;i=i+1)memory[i]=0;
        for(i=0;i<8192;i=i+1)physical_memory[i]=0;
        for(i=0;i<24;i=i+1)values[i*32+:32]=32'habc00000+i;
        repeat(4)tick();reset=0;cpu_reset=0;
        // Retain a panic even while periodic snapshot pauses recorder inserts.
        tick();tv=1;sel=15;ta=32'h0c0047f0;td=32'h74736554;
        tick();ta=32'h0c0047f4;td=32'h00000000;
        tick();ta=32'h0c0047f8;td=32'h00000077;
        tick();tv=0;sel=1;
        wait(text.state==8);
        emit(60);drain();
        if(lost!=0)$fatal(1,"unexpected initial drops");
        if(text_commits!=5)$fatal(1,"12-byte batching: %d",text_commits);
        wait(snapshot_commits>=1);
        k=memory[(16'hf000>>2)+255]!=0 ? (16'hf000>>2) : (16'hf400>>2);
        if(memory[k+242]!==32'habcdef00||memory[k+243]!==32'h12345678||memory[k+244]!==32'h514101c2)$fatal(1,"save progress words");
        for(i=0;i<24;i=i+1)if(memory[k+8+i]!==values[i*32+:32])$fatal(1,"monitor word %d",i);
        if(memory[k+32]!==32'h00014e47)$fatal(1,"NGD registered read pipeline %h",memory[k+32]);
        if(memory[k+32+198]!==32'h0007504e)$fatal(1,"panic metadata snapshot %h",memory[k+230]);
        wait(!capture);
        // Loader arriving during a diagnostic transaction cannot steal response.
        emit(12);wait(dv&&dr);tick();lv=1;wait(lr);tick();lv=0;wait(ld);repeat(2)tick();
        if(loads!=1)$fatal(1,"lost loader write");
        // Freeze DDR. First12 bytes form a pending batch;256 fit the FIFO.
        drain();hold=1;emit(400);repeat(4)tick();
        if(lost!=132)$fatal(1,"nonblocking overflow count %0d expected132",lost);
        hold=0;drain();
        if(memory[4]!==lost)$fatal(1,"drop header not published");
        // Warm reset splits byte generations but never resets transport/history.
        tick();cpu_reset=1;tick();cpu_reset=0;emit(24);drain();
        if(text.generation!=1)$fatal(1,"warm generation");
        before_seq=memory[3];reset=1;repeat(3)tick();reset=0;
        wait(text.state==8);emit(12);drain();
        if(memory[3]<=before_seq)$fatal(1,"core reset reused committed sequence");
        // Finish a current snapshot after reload; independently readable slots.
        wait(snapshot_commits>=2);wait(!capture);
        repeat(30)tick();
        if(PHYSICAL)for(i=0;i<8192;i=i+1)
            if(physical_memory[i]!=={memory[i*2+1],memory[i*2]})$fatal(1,"physical final mismatch at%h",i*8);
        fd=$fopen(RING_BITS==10?"build/sim/unit-diag-ddr/guard.bin":"build/sim/unit-diag-ddr/guard-wrap.bin","wb");
        for(i=0;i<16384;i=i+1)$fwrite(fd,"%c%c%c%c",memory[i][7:0],memory[i][15:8],memory[i][23:16],memory[i][31:24]);
        $fclose(fd);
        $display("PASS DDR diagnostic snapshot/text, real NGD pipeline,12-byte packets, overflow, loader owner, reset and ring bits%0d",RING_BITS);$finish;
    end
    initial begin #20000000;$fatal(1,"diagnostic timeout state%0d text%0d fill%0d",snapshot.state,text.state,text.fill);end
endmodule
