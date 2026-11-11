`timescale 1ns/1ps
`ifndef HOST_MODULE
`define HOST_MODULE ngage_mmc_host
`endif
// Independent register/pin peer: no DUT hierarchy reads or state forcing.
module tb;
    parameter EXPECT_BASELINE = 0;
    reg clk=0,reset=1;
    always #5 clk=~clk;
    reg acc=0,we=0,wr=0,rd=0;
    reg [5:0] off=0;
    reg [3:0] be=4'hf;
    reg [31:0] wdata=0;
    wire [31:0] rmask,rdata;
    wire busy,rx_ready,tx_ready;
    wire [3:0] irq;
    wire mmc_clk,cmd_o,cmd_oe,dat_o,dat_oe;
    reg peer_cmd=1,peer_dat=1;
    wire cmd_i=cmd_oe?cmd_o:peer_cmd;
    wire dat_i=dat_oe?dat_o:peer_dat;
    integer cycles=0,cases=0,error_bit;
    reg [31:0] status,response;
    localparam [31:0] CACHE_ERROR_MASK=32'hfdffa020;
    `HOST_MODULE #(.DIV(4),.RESP_WAIT(12),.TIMEOUT_LOG2(12),.FIFO_DEPTH(16)) dut (
        .clk(clk),.reset(reset),.acc(acc),.we(we),.wr(wr),.rd(rd),.off(off),.be(be),.wdata(wdata),
        .rmask(rmask),.rdata(rdata),.busy(busy),.rx_ready(rx_ready),.tx_ready(tx_ready),.irq(irq),
        .mmc_clk(mmc_clk),.cmd_o(cmd_o),.cmd_oe(cmd_oe),.cmd_i(cmd_i),
        .dat_o(dat_o),.dat_oe(dat_oe),.dat_i(dat_i)
    );
    always @(posedge clk)begin
        cycles<=cycles+1;
        if(cycles>400000)$fatal(1,"peer timeout cases=%0d",cases);
    end
    // Polynomial long division is independent of the DUT's feedback network.
    function [6:0] crc40;
        input [39:0] value;
        reg [46:0] dividend;
        integer index;
        begin
            dividend={value,7'd0};
            for(index=46;index>=7;index=index-1)
                if(dividend[index])dividend=dividend^(47'h89<<(index-7));
            crc40=dividend[6:0];
        end
    endfunction
    function [6:0] crc120;
        input [119:0] value;
        reg [126:0] dividend;
        integer index;
        begin
            dividend={value,7'd0};
            for(index=126;index>=7;index=index-1)
                if(dividend[index])dividend=dividend^(127'h89<<(index-7));
            crc120=dividend[6:0];
        end
    endfunction
    task write_reg;
        input [5:0] address;
        input [31:0] value;
        begin
            @(negedge clk);acc=1;we=1;wr=1;rd=0;off=address;be=15;wdata=value;
            @(negedge clk);acc=0;wr=0;
        end
    endtask
    task read_reg;
        input [5:0] address;
        output [31:0] value;
        begin
            @(negedge clk);acc=1;we=0;wr=0;rd=1;off=address;be=15;
            #1;if(rmask!==32'hffffffff)$fatal(1,"unclaimed read %h",address);
            value=rdata;
            @(negedge clk);acc=0;rd=0;
        end
    endtask
    task receive_command;
        input [31:0] argument;
        reg [47:0] packet;
        integer index;
        begin
            wait(cmd_oe);packet=0;
            for(index=0;index<48;index=index+1)begin
                @(posedge mmc_clk);packet={packet[46:0],cmd_o};
            end
            if(packet[47:46]!==2'b01 || packet[45:40]!==16 || packet[39:8]!==argument ||
                packet[7:1]!==crc40(packet[47:8]) || packet[0]!==1)
                $fatal(1,"bad CMD16 wire frame %h",packet);
            wait(!cmd_oe);
        end
    endtask
    task response_peer;
        input [31:0] argument,card_status;
        input integer variant;
        reg [39:0] head;
        reg [47:0] frame;
        reg [135:0] long_frame;
        reg [119:0] long_payload;
        integer index;
        begin
            receive_command(argument);
            // Two idle clock samples before changing CMD on a falling edge.
            repeat(2)@(posedge mmc_clk);
            if(variant!=7)begin
                head={2'b00,6'd16,card_status};
                if(variant==2)head[37:32]=17; // correct CRC, wrong response index
                if(variant==3)head[38]=1;    // card transmission bit must be zero
                frame={head,crc40(head),1'b1};
                if(variant==1 || variant==9)frame[3]=!frame[3];
                if(variant==4)frame[0]=0;
                if(variant==5)begin
                    long_payload=120'h00112233445566778899aabbccddee;
                    long_frame={2'b00,6'h3f,long_payload,crc120(long_payload),1'b1};
                    for(index=135;index>=0;index=index-1)begin
                        @(negedge mmc_clk);peer_cmd=long_frame[index];
                    end
                end else begin
                    if(variant==6)frame={2'b00,6'h3f,card_status,7'h7f,1'b1};
                    for(index=47;index>=0;index=index-1)begin
                        @(negedge mmc_clk);peer_cmd=frame[index];
                    end
                end
                @(negedge mmc_clk);peer_cmd=1;
            end
        end
    endtask
    task command16;
        input [31:0] argument,card_status;
        input integer variant;
        integer index;
        reg [31:0] control;
        reg [127:0] long_result;
        reg [119:0] long_payload;
        begin
            write_reg(6'h1c,16);write_reg(6'h20,argument);
            control=5;
            if(variant==5)control=13;   // R2 type 3
            if(variant==6)control=73;   // R3 type 2, no CRC check
            if(variant==9)control=69;   // R1 with software CRC suppression
            fork
                response_peer(argument,card_status,variant);
                begin write_reg(6'h04,control);wait(irq[2]);end
            join
            read_reg(6'h18,status);
            if(variant==7)begin
                if(!status[6] || status[8])$fatal(1,"no-response status %h",status);
            end else begin
                if(!status[8] || status[3] || status[6])$fatal(1,"response/idle status %h",status);
                if(status[1] !== (variant==1))$fatal(1,"response CRC status variant%0d status%h",variant,status);
                if(variant==5)begin
                    long_result=0;
                    for(index=0;index<4;index=index+1)begin
                        read_reg(6'h20,response);long_result={long_result[95:0],response};
                    end
                    long_payload=120'h00112233445566778899aabbccddee;
                    if(long_result!=={long_payload,crc120(long_payload),1'b1})$fatal(1,"R2 response FIFO changed");
                end else begin
                    read_reg(6'h20,response);
                    if(response!==card_status)$fatal(1,"R1/R3 response FIFO changed %h expected%h",response,card_status);
                end
                read_reg(6'h18,status);
                if(status[8])$fatal(1,"response FIFO availability did not clear");
            end
        end
    endtask
    task collect_data;
        output integer length;
        reg [8191:0] bits,division;
        integer count,index,byte_index;
        reg [4:0] token;
        begin
            wait(dat_oe);count=0;bits=0;
            while(dat_oe)begin
                @(posedge mmc_clk);
                if(dat_oe)begin bits={bits[8190:0],dat_o};count=count+1;end
            end
            if(count<18 || (count-18)%8 || bits[count-1]!==0 || bits[0]!==1)
                $fatal(1,"invalid host data frame count%0d",count);
            length=(count-18)/8;
            for(byte_index=0;byte_index<length;byte_index=byte_index+1)
                if(bits[count-2-byte_index*8-:8]!==8'ha5)$fatal(1,"TX FIFO data changed");
            // Divide the data+CRC codeword by x^16+x^12+x^5+1.
            division=bits>>1;
            for(index=count-2;index>=16;index=index-1)
                if(division[index])division=division^(8192'h11021<<(index-16));
            if(division[15:0]!==0)$fatal(1,"host data CRC16 mismatch");
            token=5'b00101; // native token: start=0, accepted=010, end=1
            for(index=4;index>=0;index=index-1)begin
                @(negedge mmc_clk);peer_dat=token[index];
            end
            @(negedge mmc_clk);peer_dat=1;
        end
    endtask
    task probe_zero_length;
        input integer expected;
        integer observed;
        begin
            write_reg(6'h08,0);write_reg(6'h04,25); // type 6, data only, cached length
            fork
                collect_data(observed);
                begin
                    while(!irq[0])begin
                        @(negedge clk);acc=1;we=1;rd=0;off=6'h24;be=1;wdata=32'ha5;wr=tx_ready;
                        @(negedge clk);acc=0;wr=0;
                    end
                end
            join
            read_reg(6'h18,status);
            if(status[10:0]!==0)$fatal(1,"data phase did not retire cleanly %h",status);
            if(observed!=expected)$fatal(1,"cached length seen on DAT0=%0d expected=%0d case=%0d",observed,expected,cases);
            cases=cases+1;
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);reset=0;
        probe_zero_length(512);
        command16(64,32'h00000900,0);probe_zero_length(64);
        command16(128,32'h20000900,0);
        probe_zero_length(EXPECT_BASELINE?128:64);
        if(EXPECT_BASELINE)begin
            $display("BASELINE_BUG rejected CMD16=128 changed cached length after accepted64; next host length0 emitted128 bytes");$finish;
        end
        for(error_bit=0;error_bit<32;error_bit=error_bit+1)begin
            if(CACHE_ERROR_MASK[error_bit])begin
                command16(128,32'h00000900|(32'd1<<error_bit),0);probe_zero_length(64);
            end
        end
        // Original decoder excludes CARD_IS_LOCKED and CARD_ECC_DISABLED;
        // the state and ready bits are also status, not command rejection.
        command16(96,32'h02004900,0);probe_zero_length(96);
        command16(128,32'h00000900,1);probe_zero_length(96); // bad CRC
        command16(128,32'h00000900,2);probe_zero_length(96); // wrong index
        command16(128,32'h00000900,3);probe_zero_length(96); // wrong transmission bit
        command16(128,32'h00000900,4);probe_zero_length(96); // wrong end bit
        command16(128,32'h00000900,5);probe_zero_length(96); // R2 is not R1
        command16(128,32'h80ff8000,6);probe_zero_length(96); // type2/R3 is not R1
        command16(128,32'h00000900,7);probe_zero_length(96); // no response
        command16(128,32'h00000900,9);probe_zero_length(96); // CRC suppression cannot prove acceptance
        @(negedge clk);reset=1;repeat(4)@(negedge clk);reset=0;
        probe_zero_length(512);
        $display("PASS CMD16 accepted-length cache: %0d pin-observed probes, R1 error bits, CRC/framing/type rejection, status-only success and reset in %0d clocks",cases,cycles);$finish;
    end
endmodule
