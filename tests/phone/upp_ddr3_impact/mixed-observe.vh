 `define UPP dut.board.upp.peripherals
 integer upload_reads=0, upload_writes=0, upload_bytes=0, upload_wait=0;
 integer nos_reads=0, nos_writes=0, nos_bytes=0, nos_wait=0;
 integer mdi_reads=0, mdi_writes=0;
 integer upload_clear=0, nos_clear=0, model_clear_beats=0;
 integer pcm_ticks=0, first_sample=-1, last_sample=-1, samples_while_waiting=0;
 integer first_ram_cycle=-1, last_ram_cycle=-1;
 integer pcm_live=0, host_live=0, lcd_live=0;
 reg [31:0] pcm_hash=32'h811c9dc5;
 wire measure_upp = `UPP.local_access && `UPP.local_ready && !`UPP.clearing;
 always @(posedge clk) begin
   if (`UPP.clearing) begin
     upload_clear <= upload_clear + 1;
     nos_clear <= nos_clear + 1;
     if (`UPP.model_clear_active)
       model_clear_beats <= model_clear_beats + 1;
   end
   if (`UPP.model_access && !`UPP.model_ready) begin
     if (`UPP.upload_selected) upload_wait <= upload_wait + 1;
     if (`UPP.nosmem_selected) nos_wait <= nos_wait + 1;
   end
   if (measure_upp && `UPP.valid_lanes && (`UPP.upload_selected || `UPP.nosmem_selected)) begin
     if (first_ram_cycle < 0) first_ram_cycle <= cycles;
     last_ram_cycle <= cycles;
     if (dut.game_pcm.player.play) pcm_live <= pcm_live + 1;
     if (host_writing) host_live <= host_live + 1;
     if (pixel_words > 0 && pixel_words < 18304) lcd_live <= lcd_live + 1;
     if (`UPP.upload_selected) begin
       upload_reads <= upload_reads + !`UPP.we;
       upload_writes <= upload_writes + `UPP.we;
       if (`UPP.we) upload_bytes <= upload_bytes + $countones(`UPP.sel);
     end else begin
       nos_reads <= nos_reads + !`UPP.we;
       nos_writes <= nos_writes + `UPP.we;
       if (`UPP.we) nos_bytes <= nos_bytes + $countones(`UPP.sel);
     end
   end
   if (measure_upp && `UPP.mdi_claim && !`UPP.mdi_bad) begin
     mdi_reads <= mdi_reads + !`UPP.we;
     mdi_writes <= mdi_writes + `UPP.we;
   end
   if (dut.game_pcm.player.tick && dut.game_pcm.player.play && !done_irq) begin
     pcm_ticks <= pcm_ticks + 1;
     pcm_hash <= (pcm_hash ^ {pcm_l,pcm_r}) * 32'd16777619;
     if (first_sample<0) first_sample <= cycles;
     last_sample <= cycles;
     if (`UPP.model_access && !`UPP.model_ready)
       samples_while_waiting <= samples_while_waiting + 1;
   end
 end
 task report_upp_impact;
  begin
   $display("UPP_COVER upload_reads=%0d upload_writes=%0d upload_bytes=%0d upload_wait=%0d nos_reads=%0d nos_writes=%0d nos_bytes=%0d nos_wait=%0d mdi_reads=%0d mdi_writes=%0d",upload_reads,upload_writes,upload_bytes,upload_wait,nos_reads,nos_writes,nos_bytes,nos_wait,mdi_reads,mdi_writes);
   $display("UPP_OVERLAP first=%0d last=%0d pcm_live=%0d mmc_write_live=%0d lcd_live=%0d sample_ticks=%0d first_sample=%0d last_sample=%0d sample_while_waiting=%0d pcm_hash=%h ddr_flash_reads=%0d",first_ram_cycle,last_ram_cycle,pcm_live,host_live,lcd_live,pcm_ticks,first_sample,last_sample,samples_while_waiting,pcm_hash,dd_reads);
   $display("UPP_CLEAR upload_words=%0d nos_words=%0d modeled_beats=%0d",upload_clear,nos_clear,model_clear_beats);
  end
 endtask
 `undef UPP
