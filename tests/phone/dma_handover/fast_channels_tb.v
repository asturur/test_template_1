`timescale 1ns/1ps
module fast_channels_tb;
    reg clk=0,reset=1;
    always #5 clk=~clk;
    reg req=0,commit=0,we=0;
    reg [31:0] addr=0,din=0;
    wire claim,bad;
    wire [31:0] dout;
    wire [7:0] irq_pending,error_pending,active_channels;
    wire mem_req,pixel_valid;
    wire [24:0] mem_addr;
    wire [31:0] pixel_data;
    reg mem_ack=0;
    reg [31:0] mem_data=0;
    integer reads=0,pixels=0,ch,cancel_mode,old_pixels;
    reg sink_drained=1;
    ngage_dma_channels #(.ENGINES(1),.PRODUCTION(1)) dut (
        .clk(clk),.reset(reset),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(4'hf),
        .claim(claim),.bad(bad),.dout(dout),.irq_pending(irq_pending),.error_pending(error_pending),.active_channels(active_channels),
        .lcd_ready(1'b1),.lcd_drained(sink_drained),.source_ready(8'hff),.destination_ready(8'hff),
        .lcd_mem_req(mem_req),.lcd_mem_addr(mem_addr),.lcd_mem_accept(mem_req&&!mem_ack),.lcd_mem_ack(mem_ack),.lcd_mem_data(mem_data),
        .lcd_pixel_valid(pixel_valid),.lcd_pixel_data(pixel_data),.lcd_pixel_ready(1'b1),.lcd_pixel_error(1'b0),
        .cmd_ready(1'b1),.rsp_valid(1'b0),.rsp_error(1'b0),.rsp_data(32'b0)
    );
    always @(posedge clk)begin
        mem_ack<=0;
        if(mem_req && !mem_ack)begin
            reads<=reads+1;mem_ack<=1;mem_data<=32'h12340000+mem_addr;
        end
        if(pixel_valid)begin
            if(pixel_data!==(pixels<8 ? 32'h12340100+(pixels*4) : 32'h12340100))$fatal(1,"channel ownership/order pixel%0d data%h",pixels,pixel_data);
            pixels<=pixels+1;
        end
    end
    task wr;
        input [31:0] a,d;
        begin @(negedge clk);req=1;commit=1;we=1;addr=a;din=d;
            #1;if(!claim || bad)$fatal(1,"register decode %h",a);
            @(negedge clk);req=0;commit=0;
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);reset=0;
        wr(32'h0c120064,32'h77777777);
        for(ch=0;ch<8;ch=ch+1)begin
            wr(32'h0c120304+ch*64,1);
            wr(32'h0c120314+ch*64,32'h0a000100+ch*4);
            wr(32'h0c120318+ch*64,1);
            wr(32'h0c12031c+ch*64,32);
            wr(32'h0c120320+ch*64,32'h10121208);
            wr(32'h0c120324+ch*64,0);
            wr(32'h0c120328+ch*64,32);
            wr(32'h0c12032c+ch*64,0);
        end
        for(ch=0;ch<8;ch=ch+1)wr(32'h0c120308+ch*64,2);
        wait(active_channels==0);@(negedge clk);
        if(irq_pending!=255 || error_pending || reads!=8 || pixels!=8)$fatal(1,"fast channel completion/count");
        for(ch=0;ch<8;ch=ch+1)begin
            wr(32'h0c120304+ch*64,0);
            if(irq_pending!==((8'hff << (ch+1))&8'hff))$fatal(1,"fast channel selective ACK");
        end
        for(cancel_mode=0;cancel_mode<2;cancel_mode=cancel_mode+1)begin
            sink_drained=0;
            wr(32'h0c120304,1);
            wr(32'h0c120308,2);
            wait(dut.fast_done);
            // Cancellation coincides with the scheduler observing done while
            // the final accepted pixel is still queued at the panel boundary.
            wr(32'h0c120308,cancel_mode==0?0:2);
            repeat(5)@(negedge clk);
            if(active_channels!=1 || irq_pending)$fatal(1,"fast cancellation lost queued tail fence");
            old_pixels=pixels;
            sink_drained=1;
            if(cancel_mode==1)begin
                wait(pixels==old_pixels+1);
                @(negedge clk);sink_drained=0;
                repeat(5)@(negedge clk);
                if(active_channels!=1 || irq_pending)$fatal(1,"fast replacement completed before queued pixel");
                sink_drained=1;
                wait(irq_pending==1);
                wr(32'h0c120304,0);
            end
            repeat(5)@(negedge clk);
            if(active_channels || irq_pending)$fatal(1,"stale fast completion after drain");
        end
        $display("PASS production LCD stream eight-channel ownership, literal count, selective ACK and final queued-tail stop/restart fence");$finish;
    end
    initial begin #100000;$fatal(1,"fast channels timeout");end
endmodule
