task directed;
    integer id, prev, read_edge, response_before, mode, write_count;
    reg [31:0] addr;
    begin
        for (mode=0;mode<2;mode=mode+1) begin
        // Clean slot: L/U writes, interleaved ways in one segment, then bubble.
        read_word('h100); read_word('h1100); read_word('h100); read_word('h1100);
        stream = 5; na=0; nc=0; nr=0; held=0;
        dirty[0]=0;dirty[1]=0; measuring=1; req=1;wr=1;
        for (id=0;id<6;id=id+1) begin
            case(id)
                0: addr='h100;
                1: addr='h110;
                2: addr='h1100;
                3: addr='h104;
                4: addr='h1110;
                5: addr='h114;
            endcase
            address=addr;din=32'hfa123456 ^ (id*32'h12345);mask=15;
            prev=na;
            while(na==prev) tick();
            if(id==3) begin req=0;tick();req=1;end
        end
        // Hold an incompatible ordinary read immediately after final accept.
        address=mode ? 'h300 : 'h114;wr=0;mask=15; req=1;
        read_edge=edge_id;
        #1; // Allow combinational ready to reflect the incompatible offer.
        while(!ready) tick();
        $display("DIRECTED drain_read waited=%0d owner=%0d commit=%0d",edge_id-read_edge,dut.pipe_owner,dut.pipe_commit);
        if(nc!=6 || nr!=6) $fatal(1,"directed drain lost stores");
        measuring=0;
        tick(); req=0;
        while(!valid) tick();
        if(error || data !== golden[address>>2]) $fatal(1,"directed following read mismatch");
        tick();
        write_count=writes; clean();
        if(writes-write_count!=16) $fatal(1,"directed half clean count");
        for(id=0;id<8;id=id+1)
            if(mem['h40+id] !== golden['h40+id] || mem['h440+id] !== golden['h440+id])
                $fatal(1,"directed clean mismatch");
        write_count=writes;clean();
        if(writes!=write_count) $fatal(1,"directed dirty clear");
        $display("DIRECTED opposite_halves/interleaved_ways/bubble transition=%0d accepts=%0d commits=%0d responses=%0d clean_words=16 PASS",mode,na,nc,nr);
        end
    end
endtask
