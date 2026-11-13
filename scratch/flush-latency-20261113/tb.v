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
    wire in_payload=address>=32'h511b8000&&address<32'h511b9000;
    wire in_ram=address>=32'h80000000&&address<32'h80010000;
    reg [31:0] data;
    always @* begin
        data=0;
        if(in_program)data=program_words[address[10:2]];
        else if(in_payload)data=payload[(address-32'h511b8000)>>2];
        else if(in_ram)data=ram[address[15:2]];
        else if(address==32'h503b409c)data=32'he51ff004;
        else if(address==32'h503b40a0)data=32'h000001b8;
        else if(address==32'h503b2640)data=32'he51ff004;
        else if(address==32'h503b2644)data=32'h00000140;
        else if(address==32'h503df58c)data=32'h47184b00;
        else if(address==32'h503df590)data=32'h0000017c;
        else if(address==32'h503df3e8)data=32'h47184b00;
        else if(address==32'h503df3ec)data=32'h0000017c;
        else if(address==32'h503df0ec)data=32'h47184b00;
        else if(address==32'h503df0f0)data=32'h0000017c;
        else if(address==32'h503df11c)data=32'h47184b00;
        else if(address==32'h503df120)data=32'h0000017c;
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
                    $display("PASS ZAP I/O observer: original args/result, ARM/Thumb return, callee registers, returned flags/SP and wait%0d",WAIT_CYCLES);
                    $finish;
                end else if(in_ram)begin
                    for(j=0;j<4;j=j+1)if(sel[j])ram[address[15:2]][j*8+:8]<=value[j*8+:8];
                end else $fatal(1,"exit tracer unexpected write %h",address);
            end

        end
    end
    initial begin
        for(i=0;i<16384;i=i+1)ram[i]=0;
        $readmemh("scratch/flush-latency-20261113/program.hex",program_words);
        $readmemh("scratch/flush-latency-20261113/io_trace.hex",payload);

        repeat(5)@(negedge clk);reset=0;
    end
endmodule
