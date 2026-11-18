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
    wire in_payload=address>=32'h511ba000&&address<32'h511bb000;
    wire in_ram=((address>=32'h80000000&&address<32'h80010000)||(address>=32'h00400000&&address<32'h00410000));
    reg [31:0] data;
    always @* begin
        data=0;
        if(in_program)data=program_words[address[10:2]];
        else if(in_payload)data=payload[(address-32'h511ba000)>>2];
        else if(in_ram)data=ram[address[15:2]];
        else if(address==32'h503b409c)data=32'he51ff004;
        else if(address==32'h503b40a0)data=32'h00000184;
        else if(address==32'h5044e4e8)data=32'h47184b00;
        else if(address==32'h5044e4ec)data=32'h00000148;
        else if(address==32'h504527f0)data=32'h47184b00;
        else if(address==32'h504527f4)data=32'h00000148;
        else if(address==32'h508b88e4)data=32'h47184b00;
        else if(address==32'h508b88e8)data=32'h00000148;
        else if(address==32'h50a13500)data=32'h47184b00;
        else if(address==32'h50a13504)data=32'h00000050;
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
                    $display("PASS ZAP profile observer: original args/result, ARM/Thumb return, callee registers, returned flags/SP and wait%0d",WAIT_CYCLES);
                    $finish;
                end else if(in_ram)begin
                    for(j=0;j<4;j=j+1)if(sel[j])ram[address[15:2]][j*8+:8]<=value[j*8+:8];
                end else $fatal(1,"exit tracer unexpected write %h",address);
            end

        end
    end
    initial begin
        for(i=0;i<16384;i=i+1)ram[i]=0;
        $readmemh("scratch/flush-latency-20261113/profile-program.hex",program_words);
        $readmemh("scratch/flush-latency-20261113/profile_trace.hex",payload);

        repeat(5)@(negedge clk);reset=0;
    end
endmodule
