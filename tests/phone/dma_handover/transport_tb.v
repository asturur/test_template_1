`timescale 1ns/1ps
module transport_tb;
    reg clk=0,reset=1,cyc=0,we=1;
    reg [31:0] addr=0,data=0;
    wire claim,ready,bad,init_done,mem_req;
    wire [24:0] mem_addr;
    reg mem_ack=0;
    integer pixels=0,stopped_pixels;
    always #5 clk=~clk;
    ngage_board #(.GENERAL_DMA(1),.LCD_ENABLE(1),.LCD_DMA_ENABLE(1)) dut (
        .clk(clk),.rst(reset),.init_rst(reset),.cyc(cyc),.stb(cyc),.we(we),.commit(cyc),.adr(addr),.din(data),.sel(4'hf),
        .cpu_ack(1'b0),.cpu_err(1'b0),.cpu_rdata(32'd0),.cfg_lcd(1'b1),.cfg_keypad(1'b0),.cfg_clocks(1'b0),
        .dma_mem_req(mem_req),.dma_mem_addr(mem_addr),.dma_mem_accept(mem_req&&!mem_ack),.dma_mem_ack(mem_ack),.dma_mem_data(32'h01230abc),
        .dma_cmd_ready(1'b0),.dma_rsp_valid(1'b0),.dma_rsp_error(1'b0),.dma_rsp_data(32'd0),.dma_local_valid(1'b0),
        .claim(claim),.ready(ready),.unmodeled(bad),.init_done(init_done)
    );
    always @(posedge clk)begin
        mem_ack<=!reset&&mem_req&&!mem_ack;
        if(!reset&&dut.lcd_dma_retire&&dut.lcd_dma_pixel)pixels<=pixels+1;
    end
    task wr;
        input [31:0] a,d;
        begin
            @(negedge clk);addr=a;data=d;cyc=1;
            #1;if(dut.lcd_dma_claim ? dut.lcd_dma_bad : (!claim||!ready||bad))$fatal(1,"external fixture rejected %h",a);
            @(negedge clk);cyc=0;
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);reset=0;wait(init_done);
        wr(32'h0c121204,1);
        wr(32'h0c121200,32'h09200000);
        wr(32'h0c121208,32'h5c);
        wr(32'h0c121200,32'h8924d67f);
        wr(32'h0c120064,32'h70);
        wr(32'h0c120344,1);
        wr(32'h0c120354,32'h0a000000);
        wr(32'h0c120358,1);
        wr(32'h0c12035c,32);
        wr(32'h0c120360,32'h10121208);
        wr(32'h0c120364,0);
        wr(32'h0c120368,32);
        wr(32'h0c12036c,1023);
        wr(32'h0c120348,2);
        wait(pixels>=4);
        wr(32'h0c121204,2);
        wait(dut.upp.dma_active==0);
        repeat(5)@(negedge clk);
        stopped_pixels=pixels;
        if(pixels==0||pixels>=1024||dut.upp.general_dma_irq||dut.upp.dma_errors!=2||!dut.display.lcd.pixel_mode||dut.lcd_transport_ready)
            $fatal(1,"fast stream bypassed reset transport: pixels%0d irq%h err%h",pixels,dut.upp.general_dma_irq,dut.upp.dma_errors);
        repeat(8)@(negedge clk);
        if(pixels!=stopped_pixels)$fatal(1,"transport rejection leaked queued pixel");
        $display("PASS production fast LCD rejects midstream transport reset without success IRQ; retained prefix=%0d",pixels);$finish;
    end
    initial begin #1000000;$fatal(1,"transport timeout");end
endmodule
