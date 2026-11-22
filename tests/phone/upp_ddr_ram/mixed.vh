 wire ddr_req, ddr_we, ddr_ack, ddr_clear, ddr_clear_done;
 wire [16:2] ddr_addr;
 wire [31:0] ddr_wdata, ddr_rdata;
 wire [3:0] ddr_be;
 upp_ddr_test_peer upp_ddr (
     .clk(clk), .cold(cold), .complete(1'b1), .req(ddr_req), .we(ddr_we),
     .addr(ddr_addr), .wdata(ddr_wdata), .be(ddr_be), .ack(ddr_ack), .rdata(ddr_rdata),
     .clear(ddr_clear), .clear_done(ddr_clear_done), .pending()
 );

 integer ddr_writes[0:1], ddr_reads[0:1];
 reg [1:0] atomic_read=0, atomic_write=0, instruction_read=0, atomic_dma_overlap=0;
 integer sample_count=0, first_sample=-1, last_sample=-1;
 reg [31:0] sample_hash=32'h811c9dc5;
 integer ram_bank;
 initial begin
     for (ram_bank=0; ram_bank<2; ram_bank=ram_bank+1) begin
         ddr_writes[ram_bank]=0;
         ddr_reads[ram_bank]=0;
     end
 end

 always @(posedge clk) begin
     if (ddr_req && ddr_ack) begin
         if (ddr_we) ddr_writes[ddr_addr[16]] <= ddr_writes[ddr_addr[16]] + 1;
         else ddr_reads[ddr_addr[16]] <= ddr_reads[ddr_addr[16]] + 1;
         if (bus_lock) begin
             if (ddr_we) atomic_write[ddr_addr[16]] <= 1;
             else atomic_read[ddr_addr[16]] <= 1;
             if (lcd_line_req && !lcd_line_ready) atomic_dma_overlap[ddr_addr[16]] <= 1;
         end
         if (!ddr_we && dut.wb_code) instruction_read[ddr_addr[16]] <= 1;
     end
     if (dut.game_pcm.player.tick && dut.game_pcm.player.play && !done_irq) begin
         sample_count <= sample_count+1;
         if (first_sample<0) first_sample <= cycles;
         last_sample <= cycles;
         sample_hash <= (sample_hash ^ {pcm_l,pcm_r}) * 32'd16777619;
     end
 end

 task check_upp_ddr;
     begin
         if (atomic_read !== 2'b11 || atomic_write !== 2'b11 || atomic_dma_overlap !== 2'b11 ||
             instruction_read !== 2'b11 || upp_ddr.clear_count != 1 ||
             ddr_writes[0] != 260 || ddr_writes[1] != 260 || ddr_reads[0] < 260 || ddr_reads[1] < 260)
             $fatal(1,"DDR owner counts upload=%0d/%0d NOS=%0d/%0d SWP=%b/%b with DMA=%b fetch=%b clears=%0d",
                    ddr_reads[0],ddr_writes[0],ddr_reads[1],ddr_writes[1],
                    atomic_read,atomic_write,atomic_dma_overlap,instruction_read,upp_ddr.clear_count);
         if (sample_count != 128 || sample_hash !== 32'h175ee178 || last_sample-first_sample != 275167)
             $fatal(1,"PCM samples=%0d hash=%h first=%0d last=%0d",
                    sample_count,sample_hash,first_sample,last_sample);
         $display("PASS production UPP DDR RAM upload=%0d/%0d NOS=%0d/%0d SWP with LCD DMA waiting=%b fetch=%b PCM hash=%h",
                  ddr_reads[0],ddr_writes[0],ddr_reads[1],ddr_writes[1],
                  atomic_dma_overlap,instruction_read,sample_hash);
     end
 endtask
