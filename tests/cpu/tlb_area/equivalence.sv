`timescale 1ns/1ps
module test;
    reg clk=0,reset=1,lookup=0,fill=0,inv=0,by_mva=0,lock=0,cancel=0,ref_fill=0;
    reg [31:0] va=0,fill_va=0,inv_va=0,lock_data=0;
    reg [37:0] fill_data=0;
    wire nv,nh,ov,oh,busy;
    wire [37:0] nd,od;
    wire [31:0] nl,ol;
    always #5 clk=~clk;
    arm920_tlb_bank dut(.clk(clk),.reset(reset),.lookup(lookup),.lookup_mva(va),.result_valid(nv),.result_hit(nh),.result_payload(nd),.fill(fill),.cancel_fill(cancel),.fill_mva(fill_va),.fill_payload(fill_data),.invalidate(inv),.invalidate_mva(by_mva),.invalidate_address(inv_va),.lock_write(lock),.lock_data(lock_data),.lock_read(nl),.busy(busy));
    reference_bank reference(.clk(clk),.reset(reset),.lookup(lookup),.lookup_mva(va),.result_valid(ov),.result_hit(oh),.result_payload(od),.fill(ref_fill),.fill_mva(fill_va),.fill_payload(fill_data),.invalidate(inv),.invalidate_mva(by_mva),.invalidate_address(inv_va),.lock_write(lock),.lock_data(lock_data),.lock_read(ol));
    integer checks=0,late_hits=0,mutations=0,queued_cases=0,cancel_cases=0,i,j,waits;
    integer latency_hist[0:12],drain_hist[0:40];
    reg [31:0] rng=32'h92aa4051;
    function [31:0] next_random;
        input [31:0] value;
        begin next_random=value*32'd1664525+32'd1013904223;end
    endfunction
    task tick;begin @(negedge clk);#1;end endtask
    task drain;begin
        waits=0;
        while(busy && waits<40)begin tick();waits=waits+1;end
        drain_hist[waits]=drain_hist[waits]+1;
        if(busy || nl!==ol)$fatal(1,"mutation did not drain/readback diverged new=%h old=%h",nl,ol);
        tick();
    end endtask
    task query(input [31:0] address);
        reg saved_hit;
        reg [37:0] saved_data;
        integer latency;
        begin
            va=address;lookup=1;tick();lookup=0;tick();
            if(!ov)$fatal(1,"reference response missing");
            saved_hit=oh;saved_data=od;latency=2;
            while(!nv && latency<12)begin tick();latency=latency+1;end
            if(!nv || nh!==saved_hit || (saved_hit && nd!==saved_data))
                $fatal(1,"bank equivalence address=%h latency=%0d hit=%b/%b payload=%h/%h",address,latency,nh,saved_hit,nd,saved_data);
            if(saved_hit && latency>2)late_hits=late_hits+1;
            latency_hist[latency]=latency_hist[latency]+1;
            checks=checks+1;tick();
        end
    endtask
    task put(input [31:0] address,input [37:0] value);
        begin fill_va=address;fill_data=value;fill=1;ref_fill=1;tick();fill=0;ref_fill=0;drain();mutations=mutations+1;end
    endtask
    initial begin
        for(i=0;i<13;i=i+1)latency_hist[i]=0;
        for(i=0;i<41;i=i+1)drain_hist[i]=0;
        repeat(4)tick();reset=0;tick();
        // All 64 entries and all scan rows must remain real architectural slots.
        for(i=0;i<64;i=i+1)put(32'h40000000+i*32'h100000,{i[1:0],i[31:0],4'hd});
        for(i=0;i<64;i=i+1)query(32'h40000044+i*32'h100000);
        // Overlap in both directions: section->tiny and tiny->section.
        put(32'h60000000,{2'd0,36'h123});put(32'h60000400,{2'd3,36'h456});
        query(32'h60000010);query(32'h60000410);
        put(32'h60000000,{2'd0,36'h789});query(32'h60000410);
        for(i=0;i<400;i=i+1)begin
            rng=next_random(rng);fill_va=32'h50000000+((rng>>8)&31)*32'h100000+((rng>>20)&255)*1024;
            fill_data={rng[1:0],rng,4'hb};
            case(rng[4:2])
                0:begin lock_data={rng[10:5],rng[16:11],19'b0,rng[17]};lock=1;tick();lock=0;drain();end
                1:begin inv=1;by_mva=rng[5];inv_va=fill_va;tick();inv=0;by_mva=0;drain();end
                2:begin
                    // A CP15 mutation arriving during an older fill must drain
                    // AFTER it, including newly preserved entries.
                    fill=1;ref_fill=1;tick();fill=0;ref_fill=0;repeat(2)tick();
                    inv=1;by_mva=rng[5];inv_va=fill_va;tick();inv=0;by_mva=0;drain();queued_cases=queued_cases+1;
                end
                3:begin
                    // A context-cancelled install must not mutate even an
                    // overlapping preserved old entry. Reference never installs.
                    fill=1;ref_fill=0;tick();fill=0;repeat(2)tick();cancel=1;tick();cancel=0;drain();cancel_cases=cancel_cases+1;
                end
                default:put(fill_va,fill_data);
            endcase
            query(fill_va+32'h34);
            rng=next_random(rng);query(32'h50000000+((rng>>8)&31)*32'h100000+((rng>>20)&255)*1024+32'h10);
        end
        if(late_hits<48 || queued_cases<10 || cancel_cases<10)$fatal(1,"directed/random coverage missing");
        for(i=0;i<13;i=i+1)if(latency_hist[i])$display("AREA_EQ_LATENCY cycles=%0d queries=%0d",i,latency_hist[i]);
        for(i=0;i<41;i=i+1)if(drain_hist[i])$display("AREA_MUTATION_DRAIN waits=%0d ops=%0d",i,drain_hist[i]);
        $display("PASS bank equivalence checks=%0d late_hits=%0d mutations=%0d queued=%0d cancelled=%0d",checks,late_hits,mutations,queued_cases,cancel_cases);$finish;
    end
    initial begin #2000000;$fatal(1,"equivalence timeout");end
endmodule
