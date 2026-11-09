`timescale 1ns/1ps
module tb;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    wire cyc, stb, we, lock;
    wire [31:0] address, value, data;
    wire [3:0] sel;
    wire [2:0] cycle_type;
    wire [1:0] burst_type;
    wire access=cyc && stb;
    reg [31:0] program_words[0:255];
    reg [31:0] bootstrap_words[0:127];
    reg [31:0] ram[0:16383];
    integer cycles=0, i;
    reg [1023:0] bootstrap_file;
    wire in_program=address<1024;
    wire in_bootstrap=address>=32'h50320860 && address<32'h50320a60;
    wire in_ram=address>=32'h80000000 && address<32'h80010000;
    assign data=in_program ? program_words[address[9:2]] :
                in_bootstrap ? bootstrap_words[(address-32'h50320860)>>2] :
                in_ram ? ram[address[15:2]] : 0;
    ngage_cpu cpu(
        .clk(clk),.reset(reset),.irq(1'b0),.fiq(1'b0),.wb_lock(lock),
        .wb_cyc(cyc),.wb_stb(stb),.wb_address(address),.wb_write(we),
        .wb_write_data(value),.wb_byte_enable(sel),.wb_cycle_type(cycle_type),
        .wb_burst_type(burst_type),.wb_ack(access),.wb_read_data(data),.wb_error(1'b0)
    );
    always @(posedge clk) if(!reset) begin
        cycles<=cycles+1;
        if(cycles>50000)$fatal(1,"bootstrap CPU test timeout");
        if(access && we)begin
            if(address==32'hf0000000)begin
                if(value!=32'h50415353)$fatal(1,"bootstrap ABI assertion failed");
                $display("PASS actual ZAP bootstrap: no-op callback with null/object r0, table, clear helpers and repeat initialization");
                $finish;
            end else if(in_ram)begin
                for(i=0;i<4;i=i+1)if(sel[i])ram[address[15:2]][i*8+:8]<=value[i*8+:8];
            end else $fatal(1,"bootstrap callback wrote outside RAM: addr=%h data=%h",address,value);
        end
        if(access && !we && !in_program && !in_bootstrap && !in_ram)
            $fatal(1,"bootstrap read/fetch outside test map: %h",address);
    end
    initial begin
        for(i=0;i<256;i=i+1)program_words[i]=0;
        for(i=0;i<128;i=i+1)bootstrap_words[i]=0;
        for(i=0;i<16384;i=i+1)ram[i]=0;
        if(!$value$plusargs("bootstrap=%s",bootstrap_file))$fatal(1,"bootstrap input required");
        $readmemh("build/sim/unit-overlay-bootstrap/program.hex",program_words);
        $readmemh(bootstrap_file,bootstrap_words);
        repeat(5)@(negedge clk);reset=0;
    end
endmodule
