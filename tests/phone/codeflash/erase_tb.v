`timescale 1ns/1ps
module erase_tb;
    reg clk=0,reset=1,v=0,w=0;
    always #5 clk=~clk;
    reg [31:0] a=0,d=0;
    reg [3:0] be=3;
    wire ready,rsp,err,mv,mw,dirty,idle,pending;
    wire [2:0] array_mode;
    wire [31:0] q,ma,md;
    wire [3:0] mb;
    wire [13:0] sector;
    reg done=0,backend_pending=0;
    reg [31:0] mr=0,saved_ma,saved_md;
    reg [3:0] saved_mb;
    reg saved_mw;
    reg [31:0] pmm[0:16383];
    reg [127:0] dirty_mask=0;
    integer i,j,n,block_number,wait_cycles=0,delay=0,writes=0,marks=0;
    wire backend_ready=!backend_pending&&!done;
    ngage_codeflash dut(.clk(clk),.reset(reset),.cold_reset(1'b0),
        .array_mode(array_mode),.req_valid(v),.req_ready(ready),.req_write(w),
        .req_address(a),.req_data(d),.req_be(be),.rsp_valid(rsp),.rsp_error(err),
        .rsp_data(q),.mem_valid(mv),.mem_ready(backend_ready),.mem_write(mw),
        .mem_addr(ma),.mem_data(md),.mem_be(mb),.mem_done(done),.mem_rdata(mr),
        .dirty_valid(dirty),.dirty_sector(sector),.idle(idle),.pending(pending));
    always @(posedge clk)begin
        done<=0;
        if(mv&&backend_ready)begin
            backend_pending<=1;delay<=wait_cycles;
            saved_ma<=ma;saved_md<=md;saved_mb<=mb;saved_mw<=mw;
            if(ma<32'h31800000||ma>=32'h31810000)$fatal(1,"backend escaped PMM %h",ma);
        end
        if(backend_pending)begin
            if(delay!=0)delay<=delay-1;
            else begin
                backend_pending<=0;done<=1;mr<=pmm[saved_ma[15:2]];
                if(saved_mw)begin
                    writes<=writes+1;
                    for(j=0;j<4;j=j+1)if(saved_mb[j])pmm[saved_ma[15:2]][j*8+:8]<=saved_md[j*8+:8];
                end
            end
        end
        if(dirty)begin
            if(sector<8192||sector>=8320)$fatal(1,"dirty outside PMM");
            if(dirty_mask[sector-8192])$fatal(1,"duplicate erase dirty event %d",sector);
            dirty_mask[sector-8192]<=1;marks<=marks+1;
        end
    end
    task tick;begin @(posedge clk);#1;end endtask
    task begin_xfer(input write_op,input [31:0] addr,input [15:0] value,input [3:0] mask);
    begin
        while(!ready)tick();@(negedge clk);v=1;w=write_op;a=addr;be=mask;
        d=mask==12?{value,16'b0}:{16'b0,value};tick();@(negedge clk);v=0;
    end endtask
    task finish_xfer(input expected_error);
    begin
        n=0;while(!rsp&&n<50000)begin tick();n=n+1;end
        if(!rsp||err!==expected_error)$fatal(1,"bad response %h err%0d expected%0d",a,err,expected_error);
        tick();
    end endtask
    task command(input [31:0] addr,input [15:0] value,input expected_error);
    begin begin_xfer(1,addr,value,addr[1]?12:3);finish_xfer(expected_error);end endtask
    task read_word(input [31:0] addr);
    begin begin_xfer(0,addr,0,15);finish_xfer(0);end endtask
    task fill;
    begin
        for(i=0;i<16384;i=i+1)pmm[i]=32'h12340000+i;
        dirty_mask=0;writes=0;marks=0;
    end endtask
    task check_block(input integer selected);
    begin
        if(writes!=4096||marks!=32)$fatal(1,"erase writes%0d marks%0d",writes,marks);
        for(i=0;i<16384;i=i+1)begin
            if((i>>12)==selected)begin if(pmm[i]!==32'hffffffff)$fatal(1,"not erased %h",i*4);end
            else if(pmm[i]!==32'h12340000+i)$fatal(1,"neighbor changed %h",i*4);
        end
        for(i=0;i<128;i=i+1)if(dirty_mask[i]!==((i>>5)==selected))$fatal(1,"dirty mask %d",i);
    end endtask
    initial begin
        if(!$value$plusargs("wait=%d",wait_cycles))wait_cycles=0;
        fill();repeat(2)tick();reset=0;tick();
        command(32'h007f0000,16'hd0,1);
        command(32'h00001000,16'h20,1);
        command(32'h007f0000,16'h80,1);
        command(32'h007f0000,16'h70,0);
        read_word(32'h007f0000);if(q!==32'h00800080)$fatal(1,"status command %h",q);
        command(0,16'hf0,0);
        // Both families, all four sectors, including high-halfword commands.
        for(block_number=0;block_number<4;block_number=block_number+1)begin
            fill();
            if((block_number&1)==0)begin
                command(32'h007f0002+(block_number<<14),16'h20,0);
                if(!pending||array_mode[0])$fatal(1,"armed erase not exposed");
                command(32'h007f0000+(((block_number+1)&3)<<14),16'hd0,1);
                if(writes!=0)$fatal(1,"mismatched confirm erased");
                command(32'h007f0002+(block_number<<14),16'hd0,0);
                command(32'h007f0000,16'h70,0);
                read_word(32'h007f0000);if(q!==32'h00800080)$fatal(1,"erase status");
                command(0,16'hf0,0);
            end else begin
                command(32'haaa,16'haa,0);command(32'h554,16'h55,0);command(32'haaa,16'h80,0);
                command(32'haaa,16'haa,0);command(32'h554,16'h55,0);
                command(32'h007f0002+(block_number<<14),16'h30,0);
                if(!array_mode[0])$fatal(1,"AMD erase did not restore array mode");
            end
            check_block(block_number);
            if(pending||!idle)$fatal(1,"erase remained pending");
        end
        // An accepted erase must finish across phone reset and mark its data.
        fill();command(32'h007fc000,16'h20,0);
        begin_xfer(1,32'h007fc000,16'hd0,3);
        while(writes<17)tick();reset=1;
        n=0;while(!idle&&n<50000)begin tick();n=n+1;end
        if(!idle)$fatal(1,"reset interrupted erase drain");
        repeat(3)tick();check_block(3);reset=0;repeat(2)tick();
        // A reset before confirmation cancels setup without erasing anything.
        fill();command(32'h007f0000,16'h20,0);reset=1;repeat(3)tick();reset=0;tick();
        if(pending||writes!=0)$fatal(1,"reset failed to cancel setup");
        command(32'h007f0000,16'hd0,1);
        command(32'haaa,16'haa,0);command(32'h554,16'h55,0);command(32'haaa,16'h80,0);
        command(32'haaa,16'haa,0);command(32'h554,16'h55,0);command(32'h00001000,16'h30,1);
        command(0,16'hf0,0);if(writes!=0||pending)$fatal(1,"protected erase changed firmware");
        $display("PASS PMM Intel/AMD erase,all sectors,lanes,protection,dirty marks,reset drain/cancel wait%0d",wait_cycles);
        $finish;
    end
endmodule
