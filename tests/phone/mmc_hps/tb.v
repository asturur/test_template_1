`timescale 1ns/1ps
module tb;
    reg clk=0;always #5 clk=!clk;
    reg init_reset=1,guest_reset=0,mount=0,ro=0;
    reg [63:0] size=0;
    wire card_reset,card_mount,card_ro,busy,fault;
    wire [63:0] card_size;
    reg [31:0] lba=0;
    reg [5:0] count=0;
    reg rd=0,wr=0;
    wire ack,buff_wr;
    wire [12:0] buff_addr;
    wire [15:0] buff_data;
    wire [31:0] h_lba;
    wire [5:0] h_count;
    wire h_rd,h_wr;
    reg h_ack=0,h_we=0;
    reg [12:0] h_addr=0;
    reg [15:0] h_data=0;
    wire [15:0] h_din;
    ngage_mmc_hps dut(.clk(clk),.init_reset(init_reset),.guest_reset(guest_reset),
        .hps_img_mounted(mount),.hps_img_readonly(ro),.hps_img_size(size),
        .card_reset(card_reset),.card_img_mounted(card_mount),.card_img_readonly(card_ro),
        .card_img_size(card_size),.card_sd_lba(lba),.card_sd_blk_cnt(count),
        .card_sd_rd(rd),.card_sd_wr(wr),.card_sd_ack(ack),.card_sd_buff_addr(buff_addr),
        .card_sd_buff_dout(buff_data),.card_sd_buff_din(16'h3d92),.card_sd_buff_wr(buff_wr),
        .hps_sd_lba(h_lba),.hps_sd_blk_cnt(h_count),.hps_sd_rd(h_rd),.hps_sd_wr(h_wr),
        .hps_sd_ack(h_ack),.hps_buff_addr(h_addr),.hps_buff_dout(h_data),
        .hps_buff_wr(h_we),.hps_buff_din(h_din),.busy(busy),.fault(fault));
    reg [7:0] footer[0:511];
    reg [127:0] cid,csd;
    integer cycles=0,cases=0,mounts=0,copies=0,ack_falls=0;
    integer n,i,j,base_copies,base_mounts,base_falls;
    reg prev_ack=0;
    reg stable_req=0;
    reg [31:0] stable_lba;
    reg [5:0] stable_count;
    task fail;
        input [511:0] why;
        begin $display("FAIL MMC HPS direct case=%0d cycle=%0d %0s",cases,cycles,why);$finish(1);end
    endtask
    always @(posedge clk)begin
        cycles=cycles+1;
        if(card_ro!==1 || h_wr || h_din!==16'hffff)fail("read-only gate changed");
        if(card_mount)begin if(card_reset)fail("mount under reset");mounts=mounts+1;end
        if(buff_wr)begin
            if(card_reset || !ack || buff_addr!==h_addr || buff_data!==h_data)fail("buffer gate/lane alignment");
            copies=copies+1;
        end
        if(prev_ack && !ack && !card_reset)ack_falls=ack_falls+1;
        prev_ack=ack;
        if(stable_req && h_rd && (h_lba!==stable_lba || h_count!==stable_count))fail("owned descriptor mutated");
        stable_req=h_rd;
        stable_lba=h_lba;stable_count=h_count;
    end
    function [6:0] crc7_120;
        input [119:0] bits;
        integer k;
        reg [6:0] c;
        reg fb;
        begin c=0;for(k=119;k>=0;k=k-1)begin fb=c[6]^bits[k];c={c[5:0],1'b0};if(fb)c=c^7'h09;end crc7_120=c;end
    endfunction
    task make_footer;
        input large_capacity;
        begin
            for(i=0;i<512;i=i+1)footer[i]=(i*37)^8'ha7;
            {footer[0],footer[1],footer[2],footer[3],footer[4],footer[5],footer[6],footer[7]}="NGAGEMMC";
            footer[8]=1;
            cid=128'h0000004d695354657210000000011701;
            cid[7:0]={crc7_120(cid[127:8]),1'b1};
            csd=0;csd[127:126]=2;csd[125:122]=3;csd[95:84]=12'h015;
            csd[83:80]=9;csd[79]=1;csd[77]=1;
            if(large_capacity)begin csd[73:62]=4095;csd[49:47]=7;end
            csd[7:0]={crc7_120(csd[127:8]),1'b1};
            for(i=0;i<16;i=i+1)begin footer[16+i]=cid[127-i*8-:8];footer[32+i]=csd[127-i*8-:8];end
            footer[48]=0;footer[49]=8'hff;footer[50]=8'h80;footer[51]=0;
        end
    endtask
    task tick;begin @(posedge clk);#1;end endtask
    task settle;begin repeat(30)tick;end endtask
    task do_mount;
        input [63:0] bytes;
        begin
            cases=cases+1;
            @(negedge clk);size=bytes;mount=1;
            repeat(2)tick;
            @(negedge clk);mount=0;
        end
    endtask
    task wait_mount;
        integer end_cycle;
        begin
            end_cycle=cycles+100;
            while(!card_mount && cycles<end_cycle)tick;
            if(!card_mount || fault || card_reset || card_size!==size)fail("retained mount missing");
            tick;
        end
    endtask
    task begin_read;
        input [31:0] address;
        input [5:0] blocks_minus_one;
        integer end_cycle;
        begin
            @(negedge clk);lba=address;count=blocks_minus_one;rd=1;
            end_cycle=cycles+50;
            while(!h_rd && !fault && cycles<end_cycle)tick;
            if(!h_rd || fault || h_lba!==address || h_count!==blocks_minus_one)fail("read not advertised");
            // Mutations following capture cannot change advertised work.
            @(negedge clk);lba=32'hf0000000;count=63;
        end
    endtask
    task accept_read;
        begin
            @(negedge clk);h_ack=1;tick;
            @(negedge clk);rd=0;
        end
    endtask
    task beat;
        input [12:0] address;
        input [15:0] data;
        begin
            @(negedge clk);h_addr=address;h_data=data;h_we=1;
            tick;
            @(negedge clk);h_we=0;
        end
    endtask
    task end_read;
        begin @(negedge clk);h_ack=0;settle;end
    endtask
    task footer_read;
        input integer words;
        begin
            begin_read((size>>9)-1,0);accept_read;
            for(n=0;n<words;n=n+1)beat(n,{footer[n*2+1],footer[n*2]});
            end_read;
        end
    endtask
    task expect_fault;
        begin if(!fault || !card_reset || ack)fail("bad media/transport not quarantined");end
    endtask
    task admission;
        input [63:0] bytes;
        input large_capacity;
        begin make_footer(large_capacity);do_mount(bytes);wait_mount;footer_read(256);if(fault || ack || card_reset)fail("valid footer rejected");end
    endtask
    initial begin
        repeat(3)tick;init_reset=0;settle;
        // An already-high, unowned slot2 ACK cannot acknowledge a fresh request.
        h_ack=1;make_footer(0);do_mount(2048);repeat(8)tick;
        if(card_mount || !card_reset || ack || h_rd)fail("stale ACK admitted mount");
        h_ack=0;wait_mount;footer_read(256);
        if(fault || ack)fail("initial valid metadata failed");
        // Streaming prefixes are forwarded without waiting for the full 4KiB.
        base_copies=copies;base_falls=ack_falls;
        begin_read(0,2);accept_read;
        for(n=0;n<768;n=n+1)begin
            beat(n,16'h5a00^n);
            if(n==0 && copies!=base_copies+1)fail("prefix buffered until complete");
        end
        end_read;
        if(fault || copies!=base_copies+768 || ack_falls!=base_falls+1)fail("valid bulk read failed");
        // All original identity bytes are checked; no raw/CRC repair fallback.
        for(j=0;j<11;j=j+1)begin
            make_footer(0);
            case(j)
                0:footer[0]=0;
                1:footer[8]=2;
                2:footer[31]=footer[31]^2;
                3:footer[31]=footer[31]&8'hfe;
                4:footer[47]=footer[47]^2;
                5:footer[47]=footer[47]&8'hfe;
                6:begin footer[32]=footer[32]^8'h40;csd[127:120]=footer[32];footer[47]={crc7_120(csd[127:8]),1'b1};end
                7:begin footer[32]=footer[32]^8'h04;csd[127:120]=footer[32];footer[47]={crc7_120(csd[127:8]),1'b1};end
                8:begin footer[37]=(footer[37]&8'hf0)|8'h08;csd[87:80]=footer[37];footer[47]={crc7_120(csd[127:8]),1'b1};end
                9:footer[48]=8'h20;
                10:footer[48]=8'h40;
            endcase
            do_mount(2048);wait_mount;base_falls=ack_falls;footer_read(256);expect_fault;
            if(ack_falls!=base_falls)fail("invalid metadata exposed ACK fall");
        end
        // Payload larger than the exact advertised CSD capacity is forbidden.
        make_footer(0);do_mount(4096);wait_mount;footer_read(256);expect_fault;
        // Initial geometry rejects before any card mount or HPS transaction.
        for(j=0;j<4;j=j+1)begin
            base_mounts=mounts;
            case(j)
                0:do_mount(512);
                1:do_mount(1025);
                2:do_mount(64'd1073742848);
                3:do_mount(64'h100000000);
            endcase
            settle;expect_fault;
            if(h_rd || mounts!=base_mounts)fail("invalid size issued work");
        end
        admission(1024,0);
        admission(64'd1073742336,1);
        base_copies=copies;
        begin_read(0,7);accept_read;
        for(n=0;n<2048;n=n+1)beat(n,16'hca00^n);
        end_read;
        if(fault || copies!=base_copies+2048)fail("maximum native bulk extent failed");
        // Exact footer count and address order: short, duplicate, out-of-range.
        for(j=0;j<3;j=j+1)begin
            make_footer(0);do_mount(2048);wait_mount;base_falls=ack_falls;
            begin_read(3,0);accept_read;
            if(j==0)begin for(n=0;n<255;n=n+1)beat(n,{footer[n*2+1],footer[n*2]});end
            else begin
                for(n=0;n<9;n=n+1)beat(n,{footer[n*2+1],footer[n*2]});
                base_copies=copies;
                beat(j==1?8:8191,16'h1234);
                if(copies!=base_copies)fail("malformed halfword delivered");
            end
            end_read;expect_fault;
            if(ack_falls!=base_falls)fail("malformed read completed");
        end
        admission(2048,0);
        begin_read(0,0);accept_read;
        for(n=0;n<256;n=n+1)beat(n,n);
        base_copies=copies;beat(256,16'hdead);end_read;expect_fault;
        if(copies!=base_copies)fail("extra halfword delivered");
        admission(2048,0);begin_read(0,0);base_copies=copies;
        beat(0,16'hface);beat(8191,16'hbeef);
        if(copies!=base_copies || fault)fail("unselected shared bus writes affected request");
        accept_read;for(n=0;n<256;n=n+1)beat(n,n);end_read;
        if(fault)fail("stray bus strobe advanced ordered counter");
        // Reset before ACK retains an immutable advertised request until drain.
        admission(2048,0);begin_read(0,0);base_mounts=mounts;
        guest_reset=1;repeat(4)tick;guest_reset=0;
        if(!h_rd || h_lba!=0 || h_count!=0 || ack)fail("guest reset withdrew owned offer");
        accept_read;base_copies=copies;
        for(n=0;n<256;n=n+1)beat(n,n);
        end_read;
        if(copies!=base_copies || fault || mounts!=base_mounts+1)fail("guest reset stale transfer/remount");
        footer_read(256);if(fault)fail("metadata reload after reset failed");
        // Reset during delivery preserves only the already-delivered prefix.
        begin_read(0,0);accept_read;
        for(n=0;n<9;n=n+1)beat(n,n);
        base_copies=copies;base_mounts=mounts;
        guest_reset=1;repeat(2)tick;guest_reset=0;
        for(n=9;n<256;n=n+1)beat(n,n);
        end_read;
        if(copies!=base_copies || fault || mounts!=base_mounts+1)fail("stale reset tail escaped");
        footer_read(256);
        // Remount during an old transfer discards its tail and retains latest metadata.
        begin_read(0,0);accept_read;beat(0,16'h5555);base_copies=copies;base_mounts=mounts;
        do_mount(2048);do_mount(1024);
        // Even a malformed old-generation tail cannot quarantine the new media.
        beat(8191,16'habcd);end_read;
        if(copies!=base_copies || fault || mounts!=base_mounts+1 || card_size!=1024)fail("remount generation isolation");
        footer_read(256);if(fault)fail("new mount footer failed");
        // Init reset clears retained media but still drains advertised work.
        begin_read(0,0);base_mounts=mounts;init_reset=1;repeat(2)tick;init_reset=0;
        if(!h_rd)fail("init reset dropped advertised request");
        accept_read;beat(0,0);end_read;
        if(!card_reset || fault || mounts!=base_mounts)fail("init reset restored stale mount");
        admission(2048,0);
        @(negedge clk);wr=1;tick;wr=0;settle;expect_fault;
        if(h_wr || h_rd)fail("readonly write issued HPS work");
        admission(2048,0);
        @(negedge clk);lba=4;count=0;rd=1;tick;rd=0;settle;expect_fault;
        admission(2048,0);
        @(negedge clk);lba=3;count=0;rd=1;tick;rd=0;settle;expect_fault;
        if(h_rd)fail("regular data request exposed footer");
        admission(64'd1073742336,1);
        @(negedge clk);lba=0;count=8;rd=1;tick;rd=0;settle;expect_fault;
        if(h_rd)fail("unsupported native bulk count advertised");
        make_footer(0);do_mount(2048);wait_mount;
        @(negedge clk);lba=0;count=0;rd=1;tick;rd=0;settle;expect_fault;
        if(h_rd)fail("first request skipped original metadata");
        admission(2048,0);begin_read(0,0);base_mounts=mounts;
        init_reset=1;guest_reset=1;repeat(2)tick;init_reset=0;guest_reset=0;
        accept_read;beat(0,0);end_read;
        if(!card_reset || fault || mounts!=base_mounts)fail("combined init/guest reset replayed stale media");
        admission(2048,0);begin_read(0,0);accept_read;base_mounts=mounts;base_copies=copies;
        do_mount(0);beat(0,0);end_read;
        if(!card_reset || fault || mounts!=base_mounts || copies!=base_copies)fail("normal removal faulted or replayed media");
        admission(2048,0);
        $display("PASS MMC HPS direct cases=%0d mounts=%0d copies=%0d clocks=%0d",cases,mounts,copies,cycles);
        $finish;
    end
    initial begin #10000000;fail("watchdog");end
endmodule
