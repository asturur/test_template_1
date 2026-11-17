`define XC dut.u_zap.u_zap_core
`define XA dut.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter
`define XB `XA.cache.bank
reg [4095:0] post_cases_file;
reg [191:0] post_cases[0:63];
integer post_count=0,post_bad=0,post_j,post_i,post_match;
integer post_accepts[0:63],post_commits[0:63],post_credits[0:63];
integer post_qin=0,post_qout=0,post_overlap=0,post_last=-1,post_adjacent=0,post_late=0;
reg [31:0] post_qva[0:4095],post_qdata[0:4095],post_qpc[0:4095];
reg [3:0] post_qbe[0:4095];reg [5:0] post_qway[0:4095];
integer post_qcase[0:4095];reg [31:0] post_mask;
reg [31:0] post_irq_begin,post_irq_end,post_irq_snapshot;
integer post_irq_armed=0,post_irq_seen=0,post_irq_accepts=0,post_irq_retires=0,post_irq_snapshot_seen=0;
reg [31:0] post_s_pc;
initial begin
    if(!$value$plusargs("post_cases=%s",post_cases_file) || !$value$plusargs("post_count=%d",post_count) || post_count>64)$fatal(1,"post cases required");
    if(!$value$plusargs("post_irq_begin=%h",post_irq_begin) || !$value$plusargs("post_irq_end=%h",post_irq_end) || !$value$plusargs("post_irq_snapshot=%h",post_irq_snapshot))$fatal(1,"post IRQ markers required");
    $display("POST_IRQ_MARKERS begin=%h end=%h snapshot=%h",post_irq_begin,post_irq_end,post_irq_snapshot);
    if($value$plusargs("post_bad=%d",post_bad))begin end
    $readmemh(post_cases_file,post_cases,0,post_count-1);
    for(post_i=0;post_i<64;post_i=post_i+1)begin post_accepts[post_i]=0;post_commits[post_i]=0;post_credits[post_i]=0;end
end
task post_safety_sample;
begin
    post_s_pc=(`XC.completion_next ? `XC.postalu1_pc_plus_8_ff : `XC.postalu_pc_plus_8_ff)-8;
    if((post_s_pc>=post_irq_begin && post_s_pc<post_irq_end) ||
       (`XC.memory_pc_plus_8_ff-8>=post_irq_begin && `XC.memory_pc_plus_8_ff-8<post_irq_end))
        $display("POST_IRQ_EDGE e=%0d pc=%h wr=%0d accept=%0d req=%0d ready=%0d addr=%h pending=%0d credit=%0d cached=%0d p1=%h p2=%h next=%0d ret=%0d rpc=%h",cycles,post_s_pc,`XA.wr,`XA.cache.accept_demand,`XA.req_valid,`XA.req_ready,`XA.address,`XA.store_pending,`XA.store_credit_accept,`XA.cache_enable,`XC.postalu1_pc_plus_8_ff-8,`XC.postalu_pc_plus_8_ff-8,`XC.completion_next,retire,retire_pc);
    if(`XC.issue_store_late && `XC.issue_pc_plus_8_ff-8==post_cases[9][191:160])post_late=post_late+1;
    if(retire && retire_pc>=post_irq_begin && retire_pc<post_irq_end)post_irq_retires=post_irq_retires+1;
    if(`XC.memory_irq_ff && post_irq_armed && !old_irq_flag)post_irq_seen=post_irq_seen+1;
    post_match=-1;
    for(post_j=0;post_j<post_count;post_j=post_j+1)begin
        if(`XA.cache.accept_demand && post_s_pc==post_cases[post_j][191:160])begin
            if(post_cases[post_j][63:32]!=1 || !`XA.cache.req_write ||
               `XA.cache.req_mva!==post_cases[post_j][159:128] || `XA.cache.req_wdata!==post_cases[post_j][127:96] || `XA.cache.req_byte_enable!==4'hf)
                $fatal(1,"post independent address/data/predication/fault oracle case=%0d pc=%h",post_j,post_s_pc);
            post_accepts[post_j]=post_accepts[post_j]+1;post_match=post_j;
            if(`XA.store_credit_accept)post_credits[post_j]=post_credits[post_j]+1;
            if(post_j<4)begin
                if(post_last>=0 && cycles-post_last==1)post_adjacent=post_adjacent+1;
                post_last=cycles;
            end
            $display("POST_CASE accept=%0d e=%0d pc=%h va=%h data=%h base=%h credit=%0d pending=%0d",post_j,cycles,post_s_pc,`XA.cache.req_mva,`XA.cache.req_wdata,post_cases[post_j][95:64],`XA.store_credit_accept,`XA.store_pending);
        end
        if(`XC.rf_wen && `XC.rf_wr_addr_a==5 && `XC.memory_pc_plus_8_ff-8==post_cases[post_j][191:160])begin
            if(post_cases[post_j][63:32]!=1 || `XC.rf_wr_data_a!==post_cases[post_j][95:64])$fatal(1,"post base commit/restoration case=%0d",post_j);
            post_commits[post_j]=post_commits[post_j]+1;
        end
    end
    if(`XA.cache.accept_demand && `XA.cache.req_write && post_s_pc>=post_irq_begin && post_s_pc<post_irq_end)begin
        if(post_s_pc!==post_irq_begin+post_irq_accepts*4 || `XA.cache.req_mva!==32'h80001d40+post_irq_accepts*4 || `XA.cache.req_wdata!==32'h11223344)
            $fatal(1,"post IRQ accepted prefix/order");
        post_irq_accepts=post_irq_accepts+1;
        if(!post_irq_armed && `XA.store_pending==2)begin
            test_irq<=1;post_irq_armed=1;
            $display("POST_IRQ_ARM e=%0d pending=%0d accepted=%0d",cycles,`XA.store_pending,post_irq_accepts);
        end
    end
    if(`XA.cache.accept_demand && post_s_pc==post_irq_snapshot)begin
        if(!post_irq_armed || post_irq_seen!=1 || post_irq_accepts!=post_irq_retires ||
           `XA.cache.req_wdata!==32'h80001d40+post_irq_retires*4)$fatal(1,"post IRQ precise base/accepted/retired prefix");
        post_irq_snapshot_seen=post_irq_snapshot_seen+1;
        $display("POST_IRQ_SNAPSHOT e=%0d accepted=%0d retired=%0d base=%h",cycles,post_irq_accepts,post_irq_retires,`XA.cache.req_wdata);
    end
    if(`XA.cache.pipe_accept)begin
        if(post_qin>=4096)$fatal(1,"post ledger overflow");
        if(post_qin>post_qout && post_match>=0)post_overlap=post_overlap+1;
        post_qva[post_qin]=`XA.cache.req_mva;post_qdata[post_qin]=`XA.cache.req_wdata;
        post_qbe[post_qin]=`XA.cache.req_byte_enable;post_qway[post_qin]=`XA.cache.result_way;
        post_qpc[post_qin]=post_s_pc;post_qcase[post_qin]=post_match;post_qin=post_qin+1;
    end
    if((|`XB.lines.write_enable) && post_qout<post_qin)begin
        post_mask={28'd0,post_qbe[post_qout]}<<((post_qva[post_qout][4:2])*4);
        if(`XB.lines.write_enable!==post_mask ||
           {`XB.lines.write_way,`XB.lines.write_segment}!=={post_qway[post_qout],post_qva[post_qout][7:5]})$fatal(1,"post physical mutation slot/order");
        for(post_i=0;post_i<4;post_i=post_i+1)
            if(post_qbe[post_qout][post_i] &&
               `XB.lines.write_line[post_qva[post_qout][4:2]*32+post_i*8+:8] !==
               (post_qdata[post_qout][post_i*8+:8] ^ ((post_bad && post_qcase[post_qout]==0 && post_i==0) ? 8'h1 : 8'h0)))
                $fatal(1,"post physical byte oracle pc=%h",post_qpc[post_qout]);
        post_qout=post_qout+1;
    end
end endtask
task post_safety_finish;
begin
    for(post_i=0;post_i<post_count;post_i=post_i+1)begin
        if(post_accepts[post_i]!=post_cases[post_i][63:32] || post_commits[post_i]!=post_cases[post_i][63:32] || post_credits[post_i]!=post_cases[post_i][31:0])
            $fatal(1,"post case missing/duplicate/fallback case=%0d accept=%0d commit=%0d credit=%0d",post_i,post_accepts[post_i],post_commits[post_i],post_credits[post_i]);
    end
    if(post_qin!=post_qout || post_adjacent<2 || post_overlap<2 || post_late==0 || post_irq_seen!=1 || post_irq_snapshot_seen!=1)
        $fatal(1,"post coverage ledger=%0d/%0d adjacent=%0d overlap=%0d late=%0d IRQ=%0d/%0d",post_qin,post_qout,post_adjacent,post_overlap,post_late,post_irq_seen,post_irq_snapshot_seen);
    $display("PASS POST_SAFETY cases=%0d physical=%0d adjacent=%0d overlapping=%0d late=%0d precise_IRQ_prefix=%0d predication old_base varied_offsets same_base pre_WB device translation permission alignment older_load_fault",post_count,post_qout,post_adjacent,post_overlap,post_late,post_irq_retires);
end endtask
`undef XC
`undef XA
`undef XB
