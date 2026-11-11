`timescale 1ns/1ps
module tb;
    reg clk=0, reset=1, req=0, commit=0, we=0;
    reg [31:0] addr=0, din=0;
    reg [3:0] sel=15;
    reg [95:0] ip=0, fp=0;
    wire tc,tb,ic,ib,tr,ir,rt,rb,ri,rib,irq,fiq,r_irq,r_fiq;
    wire [31:0] td,id,r_td,r_id;
    wire [5:0] pending,r_pending;
    wire [95:0] clear,r_clear;
    integer checks=0, waits=0, n, k, offset;
    reg [31:0] rng=32'h9a128def, value;
    wire claim=tc||ic, bad=tb||ib, ready=(!tc||tr)&&(!ic||ir);
    wire [31:0] data=tc?td:id, reference_data=rt?r_td:r_id;
    always #5 clk=~clk;
`ifdef SHARED_READBACK
    wire init_done, shared_ready, shared_claim, shared_bad;
    wire [31:0] shared_data;
    wire [95:0] reference_ip = dut.irq_sources, reference_fp = dut.fiq_sources;
    assign tc=dut.timer_claim; assign tb=dut.timer_bad;
    assign ic=dut.icu_claim; assign ib=dut.icu_bad;
    assign tr=shared_ready; assign ir=shared_ready;
    assign td=shared_data; assign id=shared_data;
    assign pending=dut.timer_pending; assign clear=dut.irq_clear;
    ngage_upp_peripherals #(.TIMER_CLK_DIV(4),.NOS_TICK_HZ(64)) dut (
        .clk(clk),.rst(reset),.init_rst(reset),.cyc(req),.stb(req),
        .we(we),.commit(commit),.adr(addr),.din(din),.sel(sel),
        .claim(shared_claim),.unmodeled(shared_bad),.ready(shared_ready),.dout(shared_data),
        .irq(irq),.fiq(fiq),.init_done(init_done),
        .cfg_lcd(1'b0),.cfg_keypad(1'b0),.cfg_clocks(1'b0),
        .dma_irq_pending(1'b0),.general_dma_irq(8'd0),.sim_fiq_pending(1'b0),.keys(26'd0),
        .cbus_claim(1'b0),.cbus_bad(1'b0),.cbus_irq(1'b0),.cbus_data(32'd0),
        .route2a(16'd0),.route2c(16'd0),.route3b(16'd0),.cbus8d_written(1'b0),
        .mdi_claim(1'b0),.mdi_bad(1'b0),.mdi_data(32'd0),.mdi_events(16'd0),
        .lcd_sink_ready(1'b1),.lcd_dma_access(1'b0),.lcd_pixel_mode(1'b0),
        .dma_shadow_claim(1'b0),.lcd_direct_collision(1'b0)
    );
`else
    wire [95:0] reference_ip=ip, reference_fp=fp;
    ngage_timers #(.CLOCK_DIV(4)) timers(
        .clk(clk),.reset(reset),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(sel),
        .clear_unit1(1'b0),.sysc74_seen(1'b0),.claim(tc),.bad(tb),.dout(td),.pending_sources(pending),.ready(tr));
`endif
    ngage_timers_reference #(.CLOCK_DIV(4)) timer_reference(
        .clk(clk),.reset(reset),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(sel),
        .clear_unit1(1'b0),.sysc74_seen(1'b0),.claim(rt),.bad(rb),.dout(r_td),.pending_sources(r_pending));
`ifndef SHARED_READBACK
    ngage_icu icu(.clk(clk),.reset(reset),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(sel),
        .irq_pending(ip),.fiq_pending(fp),.claim(ic),.bad(ib),.dout(id),.irq(irq),.fiq(fiq),.irq_clear(clear),
        .timer0_rearm(1'b0),.ready(ir));
`endif
    ngage_icu_reference icu_reference(.clk(clk),.reset(reset),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(sel),
        .irq_pending(reference_ip),.fiq_pending(reference_fp),.claim(ri),.bad(rib),.dout(r_id),.irq(r_irq),.fiq(r_fiq),.irq_clear(r_clear),
        .timer0_rearm(1'b0));
    always @(negedge clk) begin
        #2;
        if({pending,irq,fiq,clear} !== {r_pending,r_irq,r_fiq,r_clear})
            $fatal(1,"RAM conversion changed live timer/IRQ state at %h",addr);
    end
    function [31:0] random_word;
        input [31:0] x;
        begin random_word=x^(x<<13); random_word=random_word^(random_word>>17); random_word=random_word^(random_word<<5); end
    endfunction
    task access;
        input [31:0] a,d;
        input write_word;
        input [3:0] mask;
        integer age;
        begin
            @(negedge clk); req=1;commit=0;we=write_word;addr=a;din=d;sel=mask;
            #1;age=0;
            while(!ready && age<4)begin @(negedge clk);#1;age=age+1;waits=waits+1;end
            if(!ready || claim!==(rt||ri) || bad!==(rb||rib))$fatal(1,"readback decode/ready %h",a);
            if(!write_word && !bad && data!==reference_data)$fatal(1,"readback %h got %h reference %h",a,data,reference_data);
            checks=checks+1;commit=1;
            @(negedge clk);req=0;commit=0;
        end
    endtask
    task fresh;
        begin
            @(negedge clk);reset=1;req=0;commit=0;@(negedge clk);reset=0;
`ifdef SHARED_READBACK
            wait(init_done); @(negedge clk);
`endif
        end
    endtask
    initial begin
        fresh();
        for(n=0;n<6;n=n+1)begin
            for(k=0;k<4;k=k+1)begin
                offset=k==0?0:k==1?12:k==2?20:28;
                access(32'h0c120a00+32*n+offset,0,0,15);
                access(32'h0c120a00+32*n+offset,32'hfedcba98^(n*37+k),1,15);
                access(32'h0c120a00+32*n+offset,0,0,15);
                access(32'h0c120a00+32*n+offset,32'hbadbad00,1,3);
                access(32'h0c120a00+32*n+offset,0,0,15);
            end
        end
        for(n=0;n<3;n=n+1)for(k=0;k<2;k=k+1)begin
            access(32'h0c120100+64*n+4*k,0,0,15);
            access(32'h0c120100+64*n+4*k,32'h87654321^(n*5+k),1,15);
            access(32'h0c120100+64*n+4*k,0,0,15);
        end
        // Counters and IRQ masks run while passive accesses insert RAM waits.
        access(32'h0c120a18,23,1,15);access(32'h0c120a10,23,1,15);access(32'h0c120a04,2,1,15);
        access(32'h0c120108,32'hffffffff,1,15);
        ip=96'h123456789abcdef0f0f0f0f0;fp=~ip;
        for(n=0;n<12000;n=n+1)begin
            rng=random_word(rng);value=rng;
            if((n%401)==0)fresh();
            if(rng[1])begin
                k=(rng>>8)%6;offset=rng[3:2]==0?0:rng[3:2]==1?12:rng[3:2]==2?20:28;
                access(32'h0c120a00+32*k+offset,value,rng[0],rng[5:4]==0?3:15);
            end else begin
                k=(rng>>8)%3;
                access(32'h0c120100+64*k+(rng[2]?4:0),value,rng[0],rng[5:4]==0?3:15);
            end
            if((n%31)==0)access(32'h0c120a10,0,0,15);
            if((n%47)==0)access(32'h0c120114,0,0,15);
        end
        // Withdraw an unaccepted read, then change owner/address and reset.
        @(negedge clk);req=1;we=0;sel=15;addr=32'h0c120a00;#1;
        if(ready)$fatal(1,"fresh raw read skipped RAM sampling");
        req=0;@(negedge clk);fresh();
        access(32'h0c120a00,0,0,15);access(32'h0c120100,0,0,15);
        $display("PASS passive timer/ICU RAM oracle: %0d transactions, %0d added read clocks; live IRQ/counters identical",checks,waits);
        $finish;
    end
    initial begin #20000000;$fatal(1,"timeout");end
endmodule
