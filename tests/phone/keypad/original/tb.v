`timescale 1ns/1ps
module tb #(parameter SYS_CLK_HZ=104000000);
    reg clk=0, reset=1, cold=1;
    always #5 clk=~clk;
    wire cyc,stb,we,ack,claim,ready,bad,init,irq;
    wire [31:0] addr,din,dout,pc,board_data;
    wire [3:0] sel;
    reg [26:0] keys=0;
    reg [31:0] program_words[0:2047];
    reg [31:0] app_words[0:262143];
    reg [31:0] ram[0:32767];
    integer cycles=0, delay=0, wait_cycles=0, i,j,events=0;
    reg [1023:0] program_path,app_path;
    wire access=cyc&&stb;
    wire in_board=addr[31:24]==8'h58;
    wire in_program=addr<8192;
    wire in_app=addr>=32'h50320000&&addr<32'h50420000;
    wire in_ram=addr>=32'h80000000&&addr<32'h80020000;
    assign ack=access&&delay>=wait_cycles&&(!in_board||ready);
    assign dout=in_program?program_words[addr[12:2]]:
                in_app?app_words[(addr-32'h50320000)>>2]:
                in_ram?ram[addr[16:2]]:in_board?board_data:0;
    ngage_cpu cpu(.clk(clk),.reset(reset),.irq(1'b0),.fiq(1'b0),
        .wb_cyc(cyc),.wb_stb(stb),.wb_write(we),.wb_address(addr),
        .wb_write_data(din),.wb_byte_enable(sel),.wb_ack(ack),
        .wb_read_data(dout),.wb_error(1'b0),.debug_pc(pc));
    ngage_board #(.KEYPAD_ENABLE(1),.SYS_CLK_HZ(SYS_CLK_HZ)) board(
        .clk(clk),.rst(reset),.init_rst(cold),.cyc(access&&in_board),
        .stb(access&&in_board),.adr(addr-32'h4c000000),.we(we),.din(din),
        .sel(sel),.commit(ack&&in_board),.keys(keys),.sim_present(1'b0),
        .cfg_lcd(1'b1),.cfg_keypad(1'b1),.cfg_clocks(1'b1),
        .dma_irq_pending(1'b0),.sim_fiq_pending(1'b0),.cpu_ack(1'b0),
        .cpu_err(1'b0),.cpu_rdata(32'b0),.claim(claim),.ready(ready),
        .unmodeled(bad),.dout(board_data),.irq(irq),.init_done(init));
    initial begin
        if(!$value$plusargs("program=%s",program_path)||!$value$plusargs("app=%s",app_path))
            $fatal(1,"program/app required");
        i=$value$plusargs("wait=%d",wait_cycles);
        $readmemh(program_path,program_words);$readmemh(app_path,app_words);
        for(i=0;i<32768;i=i+1)ram[i]=0;
        repeat(2)@(negedge clk);cold=0;wait(init);@(negedge clk);reset=0;
    end
    always @(posedge clk)if(!reset)begin
        cycles<=cycles+1;
        if(cycles>150000)$fatal(1,"timeout pc=%h",pc);
        if(!access||ack)delay<=0;else delay<=delay+1;
        if(ack&&in_board&&(!claim||bad))$fatal(1,"board rejected %h pc=%h",addr,pc);
        if(ack&&we)begin
            if(in_ram)begin
                for(j=0;j<4;j=j+1)if(sel[j])ram[addr[16:2]][j*8+:8]<=din[j*8+:8];
            end else if(addr==32'he0000000)begin keys<=din[26:0];events<=events+1;end
            else if(addr==32'hf0000000)begin
                if(din!==32'h50415353||events!=9)$fatal(1,"original key flow failed %h events=%0d pc=%h",din,events,pc);
                $display("PASS original NEM-4 keypad config/scan/ACK HZ=%0d wait=%0d cycles=%0d events=%0d",SYS_CLK_HZ,wait_cycles,cycles,events);$finish;
            end else if(!in_board)$fatal(1,"unexpected write %h pc=%h",addr,pc);
        end
    end
endmodule
