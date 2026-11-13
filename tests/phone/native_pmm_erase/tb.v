`timescale 1ns/1ps
module tb;
    reg clk=0,reset=1;
    always #5 clk=~clk;
    wire cyc,stb,we,code;
    wire [31:0] a,d,pc;
    wire [3:0] be;
    reg [31:0] program_words[0:1023],native_words[0:2047],ram[0:16383],pmm[0:16383];
    wire access=cyc&&stb;
    wire in_program=a<4096;
    wire in_native=a>=32'h5167e000&&a<32'h51680000;
    wire in_ram=a>=32'h800c0000&&a<32'h800d0000;
    wire in_flash=(a>=32'h007f0000&&a<32'h00800000)||(!code&&({a[31:2],2'b0}==0||{a[31:2],2'b0}==32'haa8||{a[31:2],2'b0}==32'h1554));
    reg issued=0;
    wire ready,rsp,error;
    wire [31:0] q;
    wire mv,mw,dirty,idle,flash_pending;
    wire [31:0] ma,md;
    wire [3:0] mb;
    wire [13:0] sector;
    reg backend_pending=0,done=0;
    reg [31:0] saved_ma,saved_md,mr=0;
    reg saved_mw;
    reg [3:0] saved_mb;
    integer cycles=0,i,j,wait_cycles=0,backend_delay=0,writes=0,marks=0,read_wait=0;
    wire accept=mv&&!backend_pending&&!done;
    wire ack=access&&(in_flash?rsp:read_wait>=wait_cycles);
    wire [31:0] data=in_flash?q:in_program?program_words[a[11:2]]:
        in_native?native_words[a[12:2]]:in_ram?ram[a[15:2]]:0;
    ngage_codeflash flash(
        .clk(clk),.reset(reset),.cold_reset(1'b0),.req_valid(access&&in_flash&&!issued),
        .req_ready(ready),.req_write(we),.req_address(a),.req_data(d),.req_be(be),
        .rsp_valid(rsp),.rsp_error(error),.rsp_data(q),.mem_valid(mv),
        .mem_ready(!backend_pending&&!done),.mem_write(mw),.mem_addr(ma),
        .mem_data(md),.mem_be(mb),.mem_done(done),.mem_rdata(mr),
        .dirty_valid(dirty),.dirty_sector(sector),.idle(idle),.pending(flash_pending)
    );
    ngage_cpu cpu(.clk(clk),.reset(reset),.irq(1'b0),.fiq(1'b0),
        .wb_code(code),.wb_cyc(cyc),.wb_stb(stb),.wb_address(a),.wb_write(we),
        .wb_write_data(d),.wb_byte_enable(be),.wb_ack(ack),.wb_error(1'b0),
        .wb_read_data(data),.debug_pc(pc),.line_ready(1'b0),.line_reject(1'b0),
        .line_valid(1'b0),.line_data(64'b0),.line_wide(1'b0),.line_last(1'b0),.line_error(1'b0));
    always @(posedge clk) if(!reset)begin
        cycles<=cycles+1;
        if(cycles>200000)$fatal(1,"native PMM erase timeout PC=%h",pc);
        if(!access||ack)read_wait<=0;else read_wait<=read_wait+1;
        if(access&&in_flash&&!issued&&ready)issued<=1;
        if(rsp)issued<=0;
        if(access&&in_flash&&rsp&&error)$fatal(1,"original NOS command rejected addr=%h data=%h PC=%h",a,d,pc);
        done<=0;
        if(accept)begin
            backend_pending<=1;backend_delay<=wait_cycles;
            saved_ma<=ma;saved_md<=md;saved_mb<=mb;saved_mw<=mw;
            if(ma<32'h31800000||ma>=32'h31810000)$fatal(1,"backend outside PMM %h",ma);
        end
        if(backend_pending)begin
            if(backend_delay!=0)backend_delay<=backend_delay-1;
            else begin
                backend_pending<=0;done<=1;mr<=pmm[saved_ma[15:2]];
                if(saved_mw)begin
                    writes<=writes+1;
                    for(j=0;j<4;j=j+1)if(saved_mb[j])pmm[saved_ma[15:2]][j*8+:8]<=saved_md[j*8+:8];
                end
            end
        end
        if(dirty)begin
            if(sector<8224||sector>=8288)$fatal(1,"erase marked neighboring sector %d",sector);
            marks<=marks+1;
        end
        if(ack&&we)begin
            if(in_ram)begin for(j=0;j<4;j=j+1)if(be[j])ram[a[15:2]][j*8+:8]<=d[j*8+:8];end
            else if(a==32'hf0000000)begin
                if(d!=32'h50415353||writes!=8193||marks!=65||flash_pending)$fatal(1,"native result %h writes%0d marks%0d",d,writes,marks);
                for(i=0;i<16384;i=i+1)begin
                    if(i>=4096&&i<12288)begin if(pmm[i]!==(i==4096?32'hffff1234:32'hffffffff))$fatal(1,"erase missed %h",i*4);end
                    else if(pmm[i]!==32'h12340000+i)$fatal(1,"erase changed neighbor %h",i*4);
                end
                $display("PASS original NOS Intel/AMD erase and AMD program on ZAP, exact2x16KiB preservation,erase64/program1 marks, wait%0d cycles%0d",wait_cycles,cycles);
                $finish;
            end else if(!in_flash)$fatal(1,"unexpected native write %h PC%h",a,pc);
        end
        if(ack&&!we&&!in_program&&!in_native&&!in_ram&&!in_flash)$fatal(1,"unexpected native read %h PC%h",a,pc);
    end
    initial begin
        if(!$value$plusargs("wait=%d",wait_cycles))wait_cycles=0;
        for(i=0;i<16384;i=i+1)begin ram[i]=0;pmm[i]=32'h12340000+i;end
        ram[16'h8a0c>>2]=104;
        $readmemh("build/sim/unit-native-pmm-erase/program.hex",program_words);
        $readmemh("build/sim/unit-native-pmm-erase/native.hex",native_words);
        repeat(5)@(negedge clk);reset=0;
    end
endmodule
