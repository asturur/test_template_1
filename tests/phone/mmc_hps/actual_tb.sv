`timescale 1ns/1ps
module actual_tb;
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
    wire sd_ack,sd_buff_wr;
    wire [12:0] sd_buff_addr;
    wire [15:0] sd_buff_dout;
    wire [15:0] sd_buff_din;
    ngage_mmc_card dut(.clk(clk),.reset(card_reset),.mmc_clk(mmc_clk),.cmd_i(cmd_line),
        .cmd_o(cmd_o),.cmd_oe(cmd_oe),.dat_i(dat_line),.dat_o(dat_o),.dat_oe(dat_oe),
        .stop_queued(1'b0),.present(present),.write_protected(write_protected),.active(active),
        .img_mounted(card_mount),.img_readonly(card_ro),.img_size(card_size),
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
    reg [7:0] footer_version=1, opaque_seed=0;
    reg expect_present=1;
    reg [31:0] last_written_lba;
    task fail;
        input [511:0] why;
        begin $display("FAIL actual MMC HPS case=%0d clocks=%0d %0s",cases,clocks,why); $finish(1); end
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
            for(i=0;i<512;i=i+1)sidecar[i]=pattern(i,opaque_seed);
            {sidecar[0],sidecar[1],sidecar[2],sidecar[3],sidecar[4],sidecar[5],sidecar[6],sidecar[7]}="NGAGEMMC";
            sidecar[8]=footer_version;cid=128'h0000004d695354657210000000011701;
            csd=0;csd[127:126]=2;csd[125:122]=3;csd[95:84]=12'h015;csd[83:80]=9;
            csd[79]=1;csd[77]=1;
            if(large_capacity)begin csd[73:62]=3;csd[49:47]=0;end
            cid[7:0]={crc7_120(cid[127:8]),1'b1};
            csd[7:0]={crc7_120(csd[127:8]),1'b1};
            for(i=0;i<16;i=i+1)begin sidecar[16+i]=cid[127-i*8-:8];sidecar[32+i]=csd[127-i*8-:8];end
            sidecar[48]=0;sidecar[49]=8'hff;sidecar[50]=8'h80;sidecar[51]=0;
            for(i=0;i<512;i=i+1)saved_sidecar[i]=sidecar[i];
            for(i=0;i<1536;i=i+1)payload[i]=pattern(i,8'h93);
            img_size=({32'b0,nblocks}+(plain_mode?0:1))<<9;img_readonly=ro;
            mount_hps(img_readonly,img_size);
            j=0;while(!present && j<10000)begin tick;j=j+1;end
            if(present!==expect_present)fail("mount presence/version policy");
            if(expect_present)begin
            if(write_protected!==1)fail("class4 writable/WP state wrong");
            send(0,0);idle(8);
            send(1,32'h00ff8000);get_response(48);idle(8);
            send(1,32'h00ff8000);get_response(48);idle(8);
            if(response[39:8]!==32'h80ff8000)fail("CMD1 OCR mismatch");
            send(2,0);get_response(136);idle(8);
            if(!plain_mode && response[127:8]!==cid[127:8])fail("CID mismatch");
            r1(3,32'h4a110000);
            send(9,32'h4a110000);get_response(136);idle(8);
            if(!plain_mode && response[127:8]!==csd[127:8])fail("CSD mismatch");
            r1(7,32'h4a110000);r1(16,512);
            if(status[31:16]!=0)fail("ident/select/CMD16 error");
            end
        end
    endtask
    task read_data;
        input [31:0] addr;
        integer k,t;
        reg [7:0] byte_value;
        reg [15:0] crc,received_crc;
        begin
            t=0;mclk;
            while(sample_dat && t<1000)begin mclk;t=t+1;end
            if(sample_dat)fail("read data absent");
            crc=0;byte_value=0;
            for(k=0;k<4096;k=k+1)begin
                mclk;crc=crc16bit(crc,sample_dat);byte_value={byte_value[6:0],sample_dat};
                if(k%8==7 && byte_value!==image_byte(addr>>9,(addr+k/8)&511))fail("read payload mismatch");
            end
            received_crc=0;
            for(k=0;k<16;k=k+1)begin mclk;received_crc={received_crc[14:0],sample_dat};end
            if(received_crc!==crc)fail("read CRC16");
            mclk;if(!sample_dat)fail("read end bit");
        end
    endtask
    wire card_reset,card_mount,card_ro,adapter_busy,adapter_fault;
    wire [63:0] card_size;
    reg guest_reset=0;
    tri [45:0] bus;tri [35:0] ext;tri [21:0] gamma;
    reg [15:0] host_data=0;reg strobe=0,enable=0;
    assign bus[31:16]=host_data;assign bus[33]=strobe;assign bus[34]=enable;
    assign bus[35]=0;assign bus[45:38]=0;assign ext[32]=0;
    wire [3:0] mounts,rd_bus,wr_bus,h_ack;
    wire h_ro;wire [63:0] h_size;wire [31:0] h_lba[4];
    wire [5:0] h_count[4];wire [12:0] h_addr;wire [15:0] h_dout,h_din[4];wire h_we;
    reg [1:0] other_rd=0;
    assign rd_bus[1:0]=other_rd;assign wr_bus[1:0]=0;
    assign h_lba[0]=32'h100;assign h_lba[1]=32'h200;
    assign h_count[0]=0;assign h_count[1]=0;assign h_din[0]=16'h1111;assign h_din[1]=16'h2222;
    assign rd_bus[3]=0;assign wr_bus[3]=0;assign h_lba[3]=0;assign h_count[3]=0;assign h_din[3]=16'hffff;
    hps_io #(.CONF_STR("test"),.WIDE(1),.VDNUM(4),.PS2DIV(1)) hps(.clk_sys(clk),.HPS_BUS(bus),.EXT_BUS(ext),.gamma_bus(gamma),
        .img_mounted(mounts),.img_readonly(h_ro),.img_size(h_size),.sd_lba(h_lba),.sd_blk_cnt(h_count),.sd_rd(rd_bus),.sd_wr(wr_bus),.sd_ack(h_ack),
        .sd_buff_addr(h_addr),.sd_buff_dout(h_dout),.sd_buff_din(h_din),.sd_buff_wr(h_we),.ioctl_wait(1'b0),.ioctl_upload_req(1'b0),.ioctl_upload_index(8'b0),.ioctl_din(16'b0),
        .status_in(128'b0),.status_set(1'b0),.status_menumask(16'b0),.info_req(1'b0),.info(8'b0),.video_rotated(1'b0),.new_vmode(1'b0),
        .joystick_0_rumble(16'b0),.joystick_1_rumble(16'b0),.joystick_2_rumble(16'b0),.joystick_3_rumble(16'b0),.joystick_4_rumble(16'b0),.joystick_5_rumble(16'b0));
    ngage_mmc_hps transport(.clk(clk),.init_reset(reset),.guest_reset(guest_reset),
        .hps_img_mounted(mounts[2]),.hps_img_readonly(h_ro),.hps_img_size(h_size),
        .card_reset(card_reset),.card_img_mounted(card_mount),.card_img_readonly(card_ro),.card_img_size(card_size),
        .card_sd_lba(sd_lba),.card_sd_blk_cnt(sd_blk_cnt),.card_sd_rd(sd_rd),.card_sd_wr(sd_wr),.card_sd_ack(sd_ack),
        .card_sd_buff_addr(sd_buff_addr),.card_sd_buff_dout(sd_buff_dout),.card_sd_buff_din(sd_buff_din),.card_sd_buff_wr(sd_buff_wr),
        .hps_sd_lba(h_lba[2]),.hps_sd_blk_cnt(h_count[2]),.hps_sd_rd(rd_bus[2]),.hps_sd_wr(wr_bus[2]),.hps_sd_ack(h_ack[2]),
        .hps_buff_addr(h_addr),.hps_buff_dout(h_dout),.hps_buff_wr(h_we),.hps_buff_din(h_din[2]),.busy(adapter_busy),.fault(adapter_fault));
    reg mounting=0,host_busy=0,short_next=0,reset_next=0;
    reg [3:0] mount_mask=4;
    integer part,nwords,n,other_reads=0,card_reads=0,bulk_reads=0,delayed_tail_words=0,overlaps=0,forwarded=0;
    reg [31:0] current_lba;
    reg [15:0] status_word;
    reg old_ack2=0;
    always @(posedge clk)begin
        old_ack2<=h_ack[2];
        if(!reset && rd_bus[2] && |other_rd)overlaps=overlaps+1;
        if(sd_buff_wr)begin
            if(!(h_ack[2]||old_ack2)||card_reset)fail("alien slot data reached card");
            forwarded=forwarded+1;
            if(!h_ack[2])delayed_tail_words=delayed_tail_words+1;
        end
        if(card_reset && present)begin #1;if(present)fail("quarantined card remained present");end
    end
    task word_out;
        input [15:0] v;
        begin @(negedge clk);host_data=v;strobe=1;@(negedge clk);strobe=0;repeat(2)@(negedge clk);end
    endtask
    task word_last_out;
        input [15:0] v;
        begin
            @(negedge clk);host_data=v;strobe=1;
            @(negedge clk);strobe=0;enable=0;
        end
    endtask
    task begin_io;begin @(negedge clk);enable=1;end endtask
    task end_io;begin @(negedge clk);enable=0;strobe=0;repeat(3)@(negedge clk);end endtask
    task mount_hps;
        input readonly_bit;
        input [63:0] length;
        begin
            mounting=1;repeat(2)tick;wait(!host_busy);
            begin_io;word_out('h1d);word_out(length[15:0]);word_out(length[31:16]);word_out(length[47:32]);word_out(length[63:48]);end_io;
            begin_io;word_out('h1c);word_out(mount_mask|(readonly_bit?'h80:0));end_io;
            mounting=0;
        end
    endtask
    initial begin: host
        wait(!reset);
        forever begin
            wait((|rd_bus|| |wr_bus)&&!mounting);host_busy=1;
            repeat(13)@(negedge clk);
            begin_io;word_out('h16);#1;status_word=bus[15:0];part=status_word[5:2];nwords=(status_word[14:9]+1)*256;
            if(!status_word[0]||status_word[1]||part>2)fail("unexpected HPS request/write");
            word_out(0);word_out(0);#1;current_lba=bus[15:0];word_out(0);#1;current_lba=current_lba|(bus[15:0]<<16);end_io;
            if(part==2)begin
                card_reads=card_reads+1;
                if(nwords==2048)bulk_reads=bulk_reads+1;
            end else other_reads=other_reads+1;
            begin_io;word_out((part<<8)|'h17);
            for(n=0;n<nwords;n=n+1)begin
                if(short_next && part==2 && n==128)begin n=nwords;short_next=0;end
                else begin
                    if(n==nwords-1)word_last_out(part==2?{image_byte(current_lba+(n>>8),(n*2+1)&511),image_byte(current_lba+(n>>8),(n*2)&511)}:16'hac00|n);
                    else word_out(part==2?{image_byte(current_lba+(n>>8),(n*2+1)&511),image_byte(current_lba+(n>>8),(n*2)&511)}:16'hac00|n);
                    if(reset_next && part==2 && n==10)begin guest_reset=1;reset_next=0;end
                end
            end
            end_io;
            if(part<2)other_rd[part]=0;
            host_busy=0;
        end
    end
    integer base_reads,base_forwarded;
    initial begin
        repeat(4)tick;reset=0;tick;
        other_rd=3;mount(0,16,1);
        if(!present||!write_protected||adapter_fault)fail("valid production mount failed");
        r1(17,0);read_data(0);idle(8);
        r1(18,0);
        for(j=0;j<8;j=j+1)read_data(j*512);
        r1(12,0);idle(8);
        wait(!host_busy);repeat(50)tick;
        if(bulk_reads==0||other_reads!=2||overlaps==0||delayed_tail_words==0)fail("bulk/other-slot traffic fixture not exercised");
        mount_mask=1;mount_hps(0,4096);mount_mask=2;mount_hps(1,8192);mount_mask=4;
        if(card_size!=8704||!present||adapter_fault)fail("other-slot mount metadata contaminated MMC");
        r1(24,0);if(!status[26])fail("production card not forced WP");
        // A guest reset during an actual accepted HPS read suppresses old data.
        reset_next=1;guest_reset=1;repeat(2)tick;guest_reset=0;
        // A retained metadata reload is the next actual HPS request.
        wait(guest_reset);base_forwarded=forwarded;
        wait(!host_busy);repeat(20)tick;
        if(forwarded!=base_forwarded||present||!card_reset)fail("guest-reset HPS tail escaped");
        guest_reset=0;wait(present);if(adapter_fault)fail("retained metadata reload failed");
        // Unsupported original footer must remain absent; do not synthesize CID.
        footer_version=2;expect_present=0;mount(0,16,1);
        if(!adapter_fault||present)fail("unsupported footer not quarantined");
        footer_version=1;expect_present=1;mount(1,16,1);
        if(adapter_fault||!present)fail("valid remount recovery failed");
        // A physically short HPS transaction cannot publish metadata completion.
        short_next=1;expect_present=0;mount(0,16,1);
        if(!adapter_fault||present)fail("short metadata HPS transfer accepted");
        $display("PASS actual four-slot MMC HPS card_reads=%0d other_reads=%0d bulk=%0d delayed_tail_words=%0d overlaps=%0d clocks=%0d",card_reads,other_reads,bulk_reads,delayed_tail_words,overlaps,clocks);
        $finish;
    end
    initial begin #20000000;fail("watchdog");end
endmodule
