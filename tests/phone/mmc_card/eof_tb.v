`timescale 1ns/1ps
module eof_tb;
    reg clk=0; always #5 clk=!clk;
    reg reset=1, mmc_clk=0, host_cmd_oe=0, host_cmd=1, host_dat_oe=0, host_dat=1;
    wire cmd_o,cmd_oe,dat_o,dat_oe,present,write_protected,active;
    wire cmd_line=(host_cmd_oe?host_cmd:1'b1)&(cmd_oe?cmd_o:1'b1);
    wire dat_line=(host_dat_oe?host_dat:1'b1)&(dat_oe?dat_o:1'b1);
    reg img_mounted=0,img_readonly=0;
    reg [63:0] img_size=0;
    wire [31:0] sd_lba;
    wire [5:0] sd_blk_cnt;
    wire sd_rd,sd_wr;
    reg sd_ack=0,sd_buff_wr=0;
    reg [12:0] sd_buff_addr=0;
    reg [15:0] sd_buff_dout=0;
    wire [15:0] sd_buff_din;
    ngage_mmc_card dut(.clk(clk),.reset(reset),.mmc_clk(mmc_clk),.cmd_i(cmd_line),
        .cmd_o(cmd_o),.cmd_oe(cmd_oe),.dat_i(dat_line),.dat_o(dat_o),.dat_oe(dat_oe),
        .stop_queued(1'b0),.present(present),.write_protected(write_protected),.active(active),
        .img_mounted(img_mounted),.img_readonly(img_readonly),.img_size(img_size),
        .sd_lba(sd_lba),.sd_blk_cnt(sd_blk_cnt),.sd_rd(sd_rd),.sd_wr(sd_wr),.sd_ack(sd_ack),
        .sd_buff_addr(sd_buff_addr),.sd_buff_dout(sd_buff_dout),.sd_buff_din(sd_buff_din),.sd_buff_wr(sd_buff_wr));
    integer clocks=0,cases=0,reads=0,writes=0,write_requests=0;
    integer hstate=0,hdelay=0,hword=0,hgap=0,hps_delay=30;
    reg hwrite;
    reg [31:0] hlba, payload_blocks=3;
    reg [7:0] sidecar[0:511], saved_sidecar[0:511];
    reg [7:0] payload[0:1535];
    reg [127:0] csd,cid;
    reg [135:0] response;
    reg [31:0] status;
    reg sample_cmd,sample_dat;
    integer baseline,token,busy_cycles,i,j;
    reg plain_mode=0, bad_data_crc=0;
    reg [31:0] last_written_lba;
    task fail;
        input [511:0] why;
        begin $display("FAIL MMC EOF case=%0d clocks=%0d %0s",cases,clocks,why); $finish(1); end
    endtask
    function [6:0] crc7;
        input [39:0] bits;
        integer k;
        reg [6:0] c;
        reg fb;
        begin c=0; for(k=39;k>=0;k=k-1)begin fb=c[6]^bits[k];c={c[5:0],1'b0};if(fb)c=c^7'h09;end crc7=c;end
    endfunction
    function [6:0] crc7_120;
        input [119:0] bits;
        integer k;
        reg [6:0] c;
        reg fb;
        begin c=0;for(k=119;k>=0;k=k-1)begin fb=c[6]^bits[k];c={c[5:0],1'b0};if(fb)c=c^7'h09;end crc7_120=c;end
    endfunction
    function [15:0] crc16bit;
        input [15:0] c;
        input b;
        begin crc16bit={c[14:0],1'b0} ^ ((c[15]^b)?16'h1021:16'b0);end
    endfunction
    function [7:0] pattern;
        input integer offset;
        input [7:0] seed;
        begin pattern=(offset*37) ^ seed;end
    endfunction
    function [7:0] image_byte;
        input [31:0] lba;
        input integer offset;
        begin
            if(!plain_mode && lba==payload_blocks)image_byte=sidecar[offset];
            else if(lba<3)image_byte=payload[lba*512+offset];
            else image_byte=pattern(offset,8'h4d);
        end
    endfunction
    always @(posedge clk)begin
        clocks=clocks+1;
        if(!reset && ((host_cmd_oe&&cmd_oe)||(host_dat_oe&&dat_oe)))fail("bus contention");
    end
    // HPS is independent of MMC wire clocks, including a delayed grant/ACK.
    always @(negedge clk)begin
        sd_buff_wr=0;
        if(reset)begin hstate=0;sd_ack=0;end
        else case(hstate)
            0:if(sd_rd||sd_wr)begin
                if(sd_rd&&sd_wr)fail("simultaneous HPS read/write");
                if(sd_lba>payload_blocks||sd_blk_cnt!=0)fail("HPS extent outside sparse image");
                hwrite=sd_wr;hlba=sd_lba;hdelay=hps_delay;hstate=1;
                if(sd_wr)begin
                    write_requests=write_requests+1;
                    if(sd_lba>=payload_blocks)fail("sidecar/outside-payload write request");
                end
            end
            1:if(hdelay==0)begin sd_ack=1;sd_buff_addr=0;hword=0;hgap=4;hstate=2;end
              else hdelay=hdelay-1;
            2:if(hgap!=0)hgap=hgap-1;
              else if(hword<256)begin
                if(hwrite)begin
                    if(hlba<3)begin payload[hlba*512+hword*2]=sd_buff_din[7:0];payload[hlba*512+hword*2+1]=sd_buff_din[15:8];end
                    sd_buff_addr=hword+1;
                end else begin
                    sd_buff_addr=hword;sd_buff_dout={image_byte(hlba,hword*2+1),image_byte(hlba,hword*2)};sd_buff_wr=1;
                end
                hword=hword+1;hgap=4;
              end else begin
                sd_ack=0;hstate=3;hdelay=5;
                if(hwrite)begin writes=writes+1;last_written_lba=hlba;end else reads=reads+1;
              end
            3:if(hdelay==0)hstate=0;else hdelay=hdelay-1;
        endcase
    end
    task tick;begin @(posedge clk);#1;end endtask
    task mclk;
        begin
            mmc_clk=0;repeat(3)tick;
            sample_cmd=cmd_line;sample_dat=dat_line;
            mmc_clk=1;repeat(3)tick;
        end
    endtask
    task idle;
        input integer n;
        integer k;
        begin host_cmd_oe=0;host_dat_oe=0;for(k=0;k<n;k=k+1)mclk;end
    endtask
    task send;
        input [5:0] cmd;
        input [31:0] arg;
        reg [39:0] head;
        reg [47:0] frame;
        integer k;
        begin
            head={2'b01,cmd,arg};frame={head,crc7(head),1'b1};
            host_cmd_oe=1;
            for(k=47;k>=0;k=k-1)begin host_cmd=frame[k];mclk;end
            host_cmd_oe=0;host_cmd=1;
        end
    endtask
    task get_response;
        input integer n;
        integer k,waited;
        begin
            response=0;waited=0;mclk;
            while(sample_cmd && waited<80)begin waited=waited+1;mclk;end
            if(sample_cmd)fail("no response on CMD wire");
            for(k=1;k<n;k=k+1)begin mclk;response={response[134:0],sample_cmd};end
            if(!response[0])fail("response end bit");
            if(n==48 && response[7:1]!==crc7(response[47:8]) && response[45:40]!=63)fail("R1 CRC7");
            if(n==136 && response[7:1]!==crc7_120(response[127:8]))fail("R2 CRC7");
        end
    endtask
    task r1;
        input [5:0] cmd;
        input [31:0] arg;
        begin
            send(cmd,arg);get_response(48);status=response[39:8];
            if(response[45:40]!==cmd)fail("response command index");
            if(cmd!=17)idle(8);
        end
    endtask
    task mount;
        input ro;
        input [31:0] nblocks;
        input large_capacity;
        begin
            cases=cases+1;payload_blocks=nblocks;
            for(i=0;i<512;i=i+1)sidecar[i]=0;
            {sidecar[0],sidecar[1],sidecar[2],sidecar[3],sidecar[4],sidecar[5],sidecar[6],sidecar[7]}="NGAGEMMC";
            sidecar[8]=1;cid=128'h0000004d695354657210000000011701;
            csd=0;csd[95:84]=12'h015;csd[83:80]=large_capacity?12:9;
            csd[79]=1;csd[77]=1;
            if(large_capacity)begin csd[73:62]=4095;csd[49:47]=7;end
            for(i=0;i<16;i=i+1)begin sidecar[16+i]=cid[127-i*8-:8];sidecar[32+i]=csd[127-i*8-:8];end
            sidecar[48]=0;sidecar[49]=8'hff;sidecar[50]=8'h80;sidecar[51]=0;
            for(i=0;i<512;i=i+1)saved_sidecar[i]=sidecar[i];
            for(i=0;i<1536;i=i+1)payload[i]=pattern(i,8'h93);
            img_size=({32'b0,nblocks}+(plain_mode?0:1))<<9;img_readonly=ro;
            tick;img_mounted=1;tick;img_mounted=0;
            j=0;while(!present && j<10000)begin tick;j=j+1;end
            if(!present)fail("mount timeout");
            if(write_protected!==ro)fail("class4 writable/WP state wrong");
            send(0,0);idle(8);
            send(1,32'h00ff8000);get_response(48);idle(8);
            send(1,32'h00ff8000);get_response(48);idle(8);
            if(!response[39])fail("CMD1 not ready");
            send(2,0);get_response(136);idle(8);
            if(!plain_mode && response[127:8]!==cid[127:8])fail("CID mismatch");
            r1(3,32'h4a110000);
            send(9,32'h4a110000);get_response(136);idle(8);
            if(!plain_mode && response[127:8]!==csd[127:8])fail("CSD mismatch");
            r1(7,32'h4a110000);r1(16,512);
            if(status[31:16]!=0)fail("ident/select/CMD16 error");
        end
    endtask
    task write_block;
        input [7:0] seed;
        reg [15:0] crc;
        reg b;
        integer k,t;
        begin
            idle(2);host_dat_oe=1;host_dat=0;mclk;crc=0;
            for(k=0;k<4096;k=k+1)begin b=(pattern(k/8,seed)>>(7-k%8))&1;host_dat=b;crc=crc16bit(crc,b);mclk;end
            if(bad_data_crc)crc=crc^16'h0100;
            for(k=15;k>=0;k=k-1)begin host_dat=crc[k];mclk;end
            host_dat=1;mclk;host_dat_oe=0;
            t=0;mclk;while(sample_dat && t<10)begin mclk;t=t+1;end
            if(sample_dat)begin token=-1;end
            else begin
                token=0;for(k=0;k<3;k=k+1)begin mclk;token=token*2+sample_dat;end
                mclk;if(!sample_dat)fail("data response endbit");
                busy_cycles=0;mclk;
                while(!sample_dat && busy_cycles<5000)begin busy_cycles=busy_cycles+1;mclk;end
                if(!sample_dat)fail("program busy never released");
            end
            idle(4);
        end
    endtask
    task unchanged_sidecar;
        begin for(i=0;i<512;i=i+1)if(sidecar[i]!==saved_sidecar[i])fail("sidecar mutation");end
    endtask
    task expect_range;
        input [5:0] cmd;
        input [31:0] arg;
        begin r1(cmd,arg);if(!status[31] || status[26])fail("missing R1 OUT_OF_RANGE or wrong WP precedence");end
    endtask
    integer before_writes,before_reqs;
    initial begin
        baseline=$test$plusargs("baseline");repeat(4)tick;reset=0;tick;
        mount(0,3,0);
        before_writes=writes;before_reqs=write_requests;
        r1(24,1536);
        if(baseline)begin
            if(status[31:16]!=0)fail("baseline no longer reproduces acceptance");
            write_block(8'h39);
            if(token!=2 || writes!=before_writes || write_requests!=before_reqs)fail("baseline witness differs");
            unchanged_sidecar;
            $display("BASELINE_BUG CMD24 EOF R1=%h token=%0d busy_release=1 writes=0 sidecar_unchanged=1",status,token);
            $finish;
        end
        if(!status[31])fail("CMD24 writable EOF accepted");
        expect_range(25,1536);expect_range(24,2048);
        if(writes!=before_writes || write_requests!=before_reqs)fail("rejected command wrote image");
        // Padding remains readable as zeros and cannot expose the sidecar.
        r1(17,1536);if(status[31:16]!=0)fail("padding read rejected");
        j=0;mclk;while(sample_dat&&j<1000)begin mclk;j=j+1;end
        if(sample_dat)fail("padding read missing");
        for(i=0;i<4112;i=i+1)begin mclk;if(sample_dat)fail("padding data/CRC not zero");end
        mclk;if(!sample_dat)fail("read endbit");idle(8);
        // Below EOF writes persist every exact byte; HPS busy must cover delay.
        hps_delay=600;
        r1(24,512);if(status[31:16]!=0)fail("valid write rejected");
        write_block(8'h67);
        if(token!=2||writes!=before_writes+1||last_written_lba!=1||busy_cycles<90)fail("valid delayed write completion");
        for(i=0;i<512;i=i+1)if(payload[512+i]!==pattern(i,8'h67))fail("persisted bytes mismatch");
        before_writes=writes;bad_data_crc=1;
        r1(24,0);write_block(8'hc3);bad_data_crc=0;
        if(token!=5||writes!=before_writes)fail("CRC rejection changed or wrote payload");
        r1(13,32'h4a110000);if(status[12:9]!=4)fail("CRC rejection recovery state");
        // CMD25 stops before accepting any block beyond the last payload block.
        before_writes=writes;before_reqs=write_requests;
        r1(25,1024);if(status[31:16]!=0)fail("last payload multiwrite rejected");
        write_block(8'h7b);if(token!=2||writes!=before_writes+1)fail("last valid multiwrite missing");
        for(i=0;i<512;i=i+1)if(payload[1024+i]!==pattern(i,8'h7b))fail("last valid bytes mismatch");
        r1(13,32'h4a110000);if(!status[31])fail("CMD25 EOF continuation not reported");
        write_block(8'hbe);if(token!=-1||writes!=before_writes+1||write_requests!=before_reqs+1)fail("CMD25 wrote beyond EOF");
        r1(12,0);r1(13,32'h4a110000);if(status[12:9]!=4)fail("CMD12 did not return TRAN");
        unchanged_sidecar;
        // Read-only flag wins over range rejection for an otherwise writable CSD.
        mount(1,3,0);before_writes=writes;
        r1(24,1536);if(!status[26]||status[31])fail("WP precedence over payload EOF");
        r1(25,2048);if(!status[26]||status[31])fail("WP precedence over CSD capacity");
        if(writes!=before_writes)fail("read-only write occurred");
        // Plain one-sector image advertises the default minimum four sectors.
        plain_mode=1;mount(0,1,0);
        expect_range(24,512);expect_range(25,512);
        before_writes=writes;before_reqs=write_requests;
        r1(25,0);write_block(8'h83);
        if(token!=2||writes!=before_writes+1||last_written_lba!=0)fail("plain valid write failed");
        r1(13,32'h4a110000);if(!status[31])fail("plain multiwrite EOF missing");
        write_block(8'h84);if(token!=-1||write_requests!=before_reqs+1)fail("plain multiwrite EOF accepted");
        r1(12,0);plain_mode=0;
        // Above-32-bit payload arithmetic: fffffe00+512 must not wrap to zero.
        mount(0,32'h007fffff,1);
        expect_range(24,32'hfffffe00);expect_range(25,32'hfffffe00);
        r1(24,32'hfffffc00);if(status[31:16]!=0)fail("last legal 32-bit-edge command rejected");
        // Reset/remount cancels that accepted command without forcing internals.
        mount(0,32'h00800000,1);before_writes=writes;
        r1(25,32'hfffffe00);if(status[31:16]!=0)fail("4GiB last-block command rejected");
        write_block(8'h56);if(token!=2||writes!=before_writes+1||last_written_lba!=32'h007fffff)fail("4GiB last valid block failed");
        r1(13,32'h4a110000);if(!status[31])fail("4GiB continuation wrapped");
        write_block(8'h57);if(token!=-1||writes!=before_writes+1)fail("wrapped write reached LBA0");
        r1(12,0);unchanged_sidecar;
        $display("PASS MMC payload EOF wire protocol mounts=%0d HPS_reads=%0d HPS_writes=%0d clocks=%0d",cases,reads,writes,clocks);
        $finish;
    end
    initial begin #20000000;fail("global timeout");end
endmodule
