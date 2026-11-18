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
    reg [7:0] expected[0:164];
    integer printed=0;
    wire access=cyc&&stb;
    reg [3:0] delay_count=0;
    wire ack=access&&delay_count==WAIT_CYCLES;
    wire in_program=address<2048;
    wire in_payload=address>=32'h511bd000&&address<32'h511be000;
    wire in_ram=((address>=32'h80000000&&address<32'h80010000)||(address>=32'h800c0000&&address<32'h800d0000)||(address>=32'h80020000&&address<32'h80030000));
    reg [31:0] data;
    always @* begin
        data=0;
        if(in_program)data=program_words[address[10:2]];
        else if(in_payload)data=payload[(address-32'h511bd000)>>2];
        else if(in_ram)data=ram[address[15:2]];
        else if(address==32'h5159a198)data=32'h46c04778;
        else if(address==32'h5159a19c)data=32'he51ff004;
        else if(address==32'h5159a1a0)data=32'h000000b8;

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
                    if(value!=32'h50415353||printed!=165)$fatal(1,"exit tracer ABI assertion");
                    $display("PASS ZAP MTC observer: original message/action/state/caller, original args/result, ARM/Thumb return, callee registers, entry and returned flags/SP and wait%0d",WAIT_CYCLES);
                    $finish;
                end else if(address==32'h59000000)begin
                    if(printed>=165||value[7:0]!==expected[printed])$fatal(1,"lookup output byte %0d got%h",printed,value);
                    printed<=printed+1;
                end else if(in_ram)begin
                    for(j=0;j<4;j=j+1)if(sel[j])ram[address[15:2]][j*8+:8]<=value[j*8+:8];
                end else $fatal(1,"exit tracer unexpected write %h",address);
            end

        end
    end
    initial begin
        for(i=0;i<16384;i=i+1)ram[i]=0;
        for(i=0;i<6;i=i+1)ram[(16'h4388>>2)+i]=32'h03020100+32'h04040404*i;
        $readmemh("scratch/board-debug-91045a6-20261113/mtc/program.hex",program_words);
        $readmemh("scratch/board-debug-91045a6-20261113/mtc/expected.hex",expected);
        $readmemh("scratch/board-debug-91045a6-20261113/mtc/trace.hex",payload);

        repeat(5)@(negedge clk);reset=0;
    end
endmodule
