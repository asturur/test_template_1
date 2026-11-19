// The test's backing-file peer keeps the same packet setup and per-halfword
// cadence in both modes. The 4 KiB candidate validates the complete host
// buffer before serving eight existing 512-byte restore requests locally.
reg [1:0] model_ack = 0;
reg [12:0] model_addr = 0;
reg [15:0] model_data = 0;
reg model_we = 0;
assign ack = model_ack;
assign ha = model_addr;
assign hd = model_data;
assign hwe = model_we;

integer cycle = 0, host_wait = 8;
integer host_reads = 0, c_reads = 0, pmm_reads = 0, host_writes = 0;
integer host_halfwords = 0, mount_start, mount_write_start;
integer saved_slot = -1, saved_lba = -1;
reg [15:0] host_buffer[0:2047];
bit short_packet = 0, replace_image = 0, first_request = 1;
always @(posedge clk) cycle <= cycle + 1;
always @(posedge clk)
 if (reset || mount != 0) begin
  saved_slot = -1;
  saved_lba = -1;
 end

initial begin : host_peer
 integer slot, file_lba, disk_lba, base, nwords, received, sector_words;
 bit host_write;
 void'($value$plusargs("host_wait=%d", host_wait));
 short_packet = $test$plusargs("short");
 replace_image = $test$plusargs("replace");
 forever begin
  @(negedge clk);
  while (reset || !(|rd || |wr)) @(negedge clk);
  slot = rd[1] || wr[1] ? 1 : 0;
  file_lba = slot ? int'(lba1) : int'(lba);
  if (file_lba >= (slot ? 128 : 8192)) $fatal(1, "raw LBA outside selected image");
  disk_lba = file_lba + (slot ? 8192 : 0);
  host_write = |wr;
  sector_words = 256;
  if (host_write) begin
   host_writes++;
   repeat(host_wait) @(negedge clk);
   model_ack = 2'b01 << slot;
   for (integer word_index=0; word_index<256; word_index++) begin
    model_addr = 13'(word_index);
    repeat(2) @(negedge clk);
    disk[disk_lba*256+word_index] = hout;
   end
  end else if (HPS_BATCH == 1) begin
   base = file_lba & ~7;
   if (base + 8 > (slot ? 128 : 8192)) $fatal(1, "4 KiB request outside selected image");
   if (saved_slot != slot || saved_lba != base) begin
    if (file_lba != base) $fatal(1,"unaligned first sector of 4 KiB restore");
    host_reads++;
    if (slot) pmm_reads++; else c_reads++;
    repeat(host_wait) @(negedge clk);
    nwords = first_request && short_packet ? 2047 : 2048;
    for (received = 0; received<nwords; received++) begin
     repeat(2) @(negedge clk);
     if (replace_image && first_request && received == 100) begin
      image_size = slot ? 65536 : 4194304;
      mount = 2'b01 << slot;
      @(negedge clk);
      mount = 0;
     end
     host_buffer[received] = disk[(base+(slot ? 8192 : 0))*256+received];
    end
    host_halfwords += received;
    if (received == 2048 && !error) begin
     saved_slot = slot;
     saved_lba = base;
    end else sector_words = 0;
   end
   if (!error) begin
    model_ack = 2'b01 << slot;
    for (integer word_index=0; word_index<sector_words; word_index++) begin
     model_addr = 13'(word_index);
     model_data = host_buffer[(file_lba-base)*256+word_index];
     model_we = 1;
     @(negedge clk);
    end
   end
  end else begin
   host_reads++;
   if (slot) pmm_reads++; else c_reads++;
   repeat(host_wait) @(negedge clk);
   model_ack = 2'b01 << slot;
   sector_words = first_request && short_packet ? 255 : 256;
   for (integer word_index=0; word_index<sector_words; word_index++) begin
    model_addr = 13'(word_index);
    model_data = disk[disk_lba*256+word_index];
    model_we = 1;
    @(negedge clk);
    model_we = 0;
    @(negedge clk);
   end
   host_halfwords += sector_words;
  end
  first_request = 0;
  model_we = 0;
  // Give the selected core request time to sample its ACK even for an
  // invalid packet with no data. The manager then reports a short read.
  @(negedge clk);
  model_ack = 0;
  while ((|rd || |wr) && !error) @(negedge clk);
 end
end

task report_restore(input string phase);
 if (host_reads != (HPS_BATCH ? 1040 : 8320) ||
     c_reads != (HPS_BATCH ? 1024 : 8192) ||
     pmm_reads != (HPS_BATCH ? 16 : 128) ||
     host_halfwords != 2129920)
  $fatal(1, "incorrect raw restore volume/slot ledger");
 $display("RESTORE %s clocks=%0d reads=%0d c=%0d pmm=%0d bytes=%0d ddr_write=%0d",
          phase, cycle-mount_start, host_reads, c_reads, pmm_reads, 2*host_halfwords, writes-mount_write_start);
 host_reads=0;
 c_reads=0;
 pmm_reads=0;
 host_halfwords=0;
endtask
