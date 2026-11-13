`timescale 1ns/1ps
module tb;
    parameter WAIT_CYCLES=0;
    reg clk=0,reset=1;
    always #5 clk=~clk;
    wire cyc,stb,we,code;
    wire [31:0] address,value;
    wire [3:0] sel;
    reg [31:0] program_words[0:511],payload[0:1023],ram[0:16383];
    reg [31:0] hooks[0:5];
    integer i,j,cycles=0,hook_index;
    wire access=cyc&&stb;
    reg [3:0] delay_count=0;
    wire ack=access&&delay_count==WAIT_CYCLES;
    wire in_program=address<2048;
    wire in_payload=address>=32'h511b6000&&address<32'h511b7000;
    wire in_ram=address>=32'h80000000&&address<32'h80010000;
    reg [31:0] data;
    always @* begin
        hook_index=-1;
        case(address)
            32'h503b4718,32'h503b471c,32'h503b4720:hook_index=0;
            32'h503b46e0,32'h503b46e4,32'h503b46e8:hook_index=1;
            32'h503b7fb8,32'h503b7fbc,32'h503b7fc0:hook_index=2;
            32'h503b7fe4,32'h503b7fe8,32'h503b7fec:hook_index=3;
            32'h503b8010,32'h503b8014,32'h503b8018:hook_index=4;
            32'h503a2b48:hook_index=5;
        endcase
        data=0;
        if(in_program)data=program_words[address[10:2]];
        else if(in_payload)data=payload[(address-32'h511b6000)>>2];
        else if(in_ram)data=ram[address[15:2]];
        else if(address==32'h503b409c)data=32'he51ff004; // LDR pc,[pc,#-4]
        else if(address==32'h503b40a0)data=program_words[511];
        else if(address==32'h503b1b78)data=32'he12fff1e; // Original bounds-failure destination.
        else if(hook_index>=0)begin
            if(address==32'h503b4718||address==32'h503b46e0||address==32'h503b7fb8||address==32'h503b7fe4||address==32'h503b8010||address==32'h503a2b48)
                data=hooks[hook_index];
            else if(address==32'h503b471c||address==32'h503b46e4||address==32'h503b7fbc||address==32'h503b7fe8||address==32'h503b8014)
                data=32'he8bd4000; // Replay original PUSH then checked POP/BX continuation.
            else data=32'he12fff1e;
        end
    end
    ngage_cpu cpu(.clk(clk),.reset(reset),.irq(1'b0),.fiq(1'b0),
        .wb_code(code),.wb_cyc(cyc),.wb_stb(stb),.wb_address(address),.wb_write(we),
        .wb_write_data(value),.wb_byte_enable(sel),.wb_ack(ack),.wb_error(1'b0),.wb_read_data(data));
    always @(posedge clk)begin
        if(reset||!access||ack)delay_count<=0;
        else delay_count<=delay_count+1'b1;
        if(!reset)begin
            cycles<=cycles+1;
            if(cycles>50000)$fatal(1,"exit tracer timeout");
            if(access&&ack&&we)begin
                if(address==32'hf0000000)begin
                    if(value!=32'h50415353)$fatal(1,"exit tracer ABI assertion");
                    $display("PASS ZAP exit tracer: five exit hooks and descriptor failure, ARM/Thumb return, argument/volatile register/flags/SP preservation and wait%0d",WAIT_CYCLES);
                    $finish;
                end else if(in_ram)begin
                    for(j=0;j<4;j=j+1)if(sel[j])ram[address[15:2]][j*8+:8]<=value[j*8+:8];
                end else $fatal(1,"exit tracer unexpected write %h",address);
            end
            if(access&&!we&&!code&&!in_program&&!in_payload&&!in_ram&&hook_index<0&&address!=32'h503b409c&&address!=32'h503b40a0&&address!=32'h503b1b78)
                $fatal(1,"exit tracer unexpected read %h",address);
        end
    end
    initial begin
        for(i=0;i<16384;i=i+1)ram[i]=0;
        $readmemh("build/sim/unit-exit-trace/program.hex",program_words);
        $readmemh("build/sim/unit-exit-trace/payload.hex",payload);
        $readmemh("build/sim/unit-exit-trace/hooks.hex",hooks);
        repeat(5)@(negedge clk);reset=0;
    end
endmodule
