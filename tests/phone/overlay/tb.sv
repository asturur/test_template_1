`timescale 1ns/1ps
module tb;
    parameter integer OVERLAY_ID=1;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=1, fw_valid=0, fw_loading=0, enabled=0, blocked=0;
    reg download=0, wr=0;
    reg [26:0] addr=0;
    reg [15:0] data=0;
    wire wait_req, ready, loaded, applied, busy;
    wire [3:0] error;
    wire valid, write;
    wire [31:0] target, value;
    reg pending=0, done=0;
    reg [31:0] rdata=0, saved_addr, saved_data;
    reg saved_write;
    integer delay_left=0, writes=0, reads=0, cycle=0;
    reg [31:0] memory[0:5242879];
    reg [15:0] pack_words[0:4095];
    reg [1023:0] filename;
    integer size, count, i, j, n, before_writes, expected_error=0;
    reg [31:0] off, old, replacement;
    ngage_nos_overlay #(.OVERLAY_ID(OVERLAY_ID)) dut(
        .clk(clk),.reset(reset),.firmware_valid(fw_valid),.firmware_loading(fw_loading),
        .enabled(enabled),.checksum_required(enabled),.blocked(blocked),.download(download),.wr(wr),.addr(addr),.data(data),
        .wait_req(wait_req),.ready(ready),.loaded(loaded),.applied(applied),.busy(busy),.error(error),
        .mem_valid(valid),.mem_ready(!pending),.mem_write(write),.mem_addr(target),
        .mem_data(value),.mem_done(done),.mem_rdata(rdata)
    );
    always @(posedge clk) begin
        cycle<=cycle+1;
        done<=0;
        if(valid && !pending) begin
            if(target<32'h30000000 || target>=32'h313f0000 || target[1:0]!=0)
                $fatal(1,"overlay reached C:/PMM/guard or unaligned memory: %h",target);
            if(write && (!fw_valid || fw_loading || ready)) $fatal(1,"unsafe overlay write");
            saved_addr<=target;saved_data<=value;saved_write<=write;
            pending<=1;delay_left<=(cycle%5)+1;
        end
        if(pending) begin
            if(delay_left!=0) delay_left<=delay_left-1;
            else begin
                pending<=0;done<=1;
                if(saved_write) begin memory[(saved_addr-32'h30000000)>>2]<=saved_data;writes<=writes+1;end
                else begin rdata<=memory[(saved_addr-32'h30000000)>>2];reads<=reads+1;end
            end
        end
        if(cycle>500000) $fatal(1,"overlay timeout state=%0d error=%0d",dut.state,error);
    end
    function [31:0] word_at(input integer index);
        word_at={pack_words[index*2+1],pack_words[index*2]};
    endfunction
    task tick;
        begin @(posedge clk);#1;end
    endtask
    task seed;
        begin
            for(j=0;j<count;j=j+1)begin
                off=word_at(16+j*3);old=word_at(17+j*3);
                memory[off>>2]=old;
            end
            memory[5242879]=32'hcafe1234;
        end
    endtask
    task check_view(input bit on);
        begin
            for(j=0;j<count;j=j+1)begin
                off=word_at(16+j*3);old=word_at(17+j*3);replacement=word_at(18+j*3);
                if(memory[off>>2] !== (on?replacement:old))
                    $fatal(1,"wrong %0d view offset=%h got=%h",on,off,memory[off>>2]);
            end
            if(memory[5242879]!==32'hcafe1234)$fatal(1,"guard modified");
        end
    endtask
    task send(input integer corrupt);
        begin
            @(negedge clk);download=1;wr=0;tick();
            for(i=0;i<size/2-((corrupt==3)?1:0);i=i+1)begin
                while(wait_req)tick();
                @(negedge clk);addr=i*2;data=pack_words[i] ^ (((corrupt==1 && i==size/2-1) || ((corrupt==2 && i==10) || (corrupt==4 && i==4)))?16'h1:16'h0);wr=1;
                tick();@(negedge clk);wr=0;
            end
            @(negedge clk);download=0;
            repeat(8)tick();
        end
    endtask
    task wait_ready;
        begin
            n=0;
            while(!ready)begin tick();n=n+1;if(n>100000)$fatal(1,"not ready state=%0d error=%0d",dut.state,error);end
        end
    endtask
    initial begin
        if(!$value$plusargs("package=%s",filename))$fatal(1,"package required");
        $readmemh(filename,pack_words);
        if($value$plusargs("expected-error=%d",expected_error))begin end
        count=word_at(3);size=word_at(11);seed();
        repeat(3)tick();reset=0;enabled=1;
        send(0);
        if(!loaded || ready || writes!=0)$fatal(1,"autoload did not stage before firmware");
        fw_loading=1;repeat(5)tick();fw_loading=0;fw_valid=1;
        if(expected_error!=0)begin
            repeat(1000)tick();
            if(error!=expected_error || writes!=0 || ready)$fatal(1,"invalid target accepted");
            $display("PASS invalid bounds/alignment/order rejected before writes");$finish;
        end
        wait_ready();check_view(1);
        if(writes!=count || !applied)$fatal(1,"ON did not apply exactly once");
        enabled=0;tick();wait_ready();check_view(0);
        if(writes!=2*count || applied)$fatal(1,"OFF did not undo");
        // Bad CRC must never write target memory; OFF stays usable.
        before_writes=writes;send(1);repeat(4)tick();
        if(loaded || error!=2 || writes!=before_writes || !ready)$fatal(1,"bad CRC acceptance/rollback");
        check_view(0);
        send(2);
        if(loaded || error!=1 || writes!=before_writes || !ready)$fatal(1,"wrong profile accepted");
        send(4);
        if(loaded || error!=1 || writes!=before_writes || !ready)$fatal(1,"wrong component accepted");
        send(3);
        if(loaded || error!=1 || writes!=before_writes || !ready)$fatal(1,"truncated package accepted");
        send(0);wait_ready();
        // A mismatch at the LAST record proves no earlier target was written.
        off=word_at(16+(count-1)*3);old=word_at(17+(count-1)*3);
        memory[off>>2]=old^32'h76543210;before_writes=writes;enabled=1;
        repeat(50000)tick();
        if(error!=4 || ready || writes!=before_writes)$fatal(1,"target preflight not atomic");
        // Firmware reload recovers, including a mixture of already patched and
        // reloaded original words, without losing the undo table.
        fw_loading=1;fw_valid=0;seed();repeat(5)tick();fw_loading=0;fw_valid=1;
        wait_ready();check_view(1);
        fw_loading=1;fw_valid=0;
        for(j=0;j<count;j=j+2)begin off=word_at(16+j*3);memory[off>>2]=word_at(17+j*3);end
        repeat(5)tick();fw_loading=0;fw_valid=1;wait_ready();check_view(1);
        // Reloading the undo table while ON is rejected and drained, not hung.
        before_writes=writes;send(0);
        if(error!=9 || writes!=before_writes || !loaded)$fatal(1,"active package reload");
        enabled=0;tick();wait_ready();check_view(0);
        // Changing one's mind mid-application cannot release a mixed view.
        before_writes=writes;enabled=1;
        while(writes<before_writes+2)tick();enabled=0;
        wait_ready();check_view(0);
        $display("PASS overlay: real/synthetic pack, early autoload, CRC, exact ON/OFF, all-word preflight, reload, conflict drain, toggles and delayed DDR");
        $finish;
    end
endmodule
