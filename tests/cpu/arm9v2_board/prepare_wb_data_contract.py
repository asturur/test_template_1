#!/usr/bin/env python3
"""Extend the checked board guest with write-error and dirty-eviction probes."""
import argparse
from pathlib import Path


def edit(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Missing unique contract site {old!r}")
    return text.replace(old, new)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    fixture = Path(__file__).resolve().parent
    args.out.mkdir(parents=True, exist_ok=True)
    asm = (fixture / "contract.S").read_text()
    asm = edit(asm, "    msr cpsr_c,#0x13", """    // A rejected scalar store must not be acknowledged as a write.
    mov r6,#0
    str r4,[r7,#36]
    cmp r6,#1
    bne fail

    msr cpsr_c,#0x13""")
    asm = edit(asm, "    // Read-allocate both ways before dirtying them.", """    // Miss stores queue distinct strobes and data before the drain.
    ldr r9,=0x0a006380
    ldr r4,=0xaaa5126c
    str r4,[r9]
    strh r4,[r9,#6]
    strb r4,[r9,#9]
    mcr p15,0,r4,c7,c10,4
    ldr r5,[r9]
    cmp r5,r4
    bne fail
    ldrh r5,[r9,#6]
    mov r4,r4,lsl #16
    mov r4,r4,lsr #16
    cmp r5,r4
    bne fail
    ldrb r5,[r9,#9]
    cmp r5,#0x6c
    bne fail

    // Dirty both halves with distinct words; force eviction by reading two
    // other ways of this set. The peer checks backing RAM before any clean.
    ldr r9,=0x0a003000
    ldr r4,[r9]
    ldr r4,=0x94756123
    mov r5,#0
1:  str r4,[r9,r5]
    add r4,r4,#1
    add r5,r5,#4
    cmp r5,#32
    bne 1b
    add r10,r9,#0x2000
    add r11,r10,#0x2000
    ldr r4,[r10]
    ldr r4,[r11]
    ldr r4,[r10]
    ldr r4,[r11]
    mov r5,#1
    str r5,[r7,#20]

    // Read-allocate both ways before dirtying them.""")
    (args.out / "contract.S").write_text(asm)

    bench = (fixture / "contract.v").read_text()
    bench = edit(bench, "  wire [31:0] line_addr;", """  wire [31:0] line_addr;
  wire block_write;
  wire [127:0] block_data;
  reg ram_saved_block;
  reg [127:0] ram_saved_block_data;
  integer write_errors = 0, eviction_checks = 0, native_blocks = 0, word_in_block;""")
    bench = edit(bench, "      .wb_write_data(wdata),", """      .wb_write_data(wdata),
      .wb_write_block(block_write),
      .wb_block_data(block_data),""")
    bench = edit(bench, """  always @(posedge clk)
    if (!reset) begin
      cycle <= cycle + 1;""", """  always @(posedge clk)
    if (reset) begin
      ram_pending <= 0;
      slow_delay <= 0;
    end else begin
      cycle <= cycle + 1;""")
    bench = edit(bench, "cycle == 180000", "cycle == 400000")
    bench = edit(bench, "device_address == 32'h0c000020 ||",
                 "device_address == 32'h0c000020 || device_address == 32'h0c000024 ||")
    bench = edit(bench, "      if (device_error && device_address == 32'h1008) begin", """      if (device_error && device_address == 32'h0c000024) begin
        if (device_code || !device_write) $fatal(1, "Wrong rejected write packet");
        write_errors <= write_errors + 1;
      end
      if (device_error && device_address == 32'h1008) begin""")
    bench = edit(bench, "          32'hf0000000: begin", """          32'h0c000014: begin
            for (word_in_block = 0; word_in_block < 8; word_in_block = word_in_block + 1)
              if (ram[14'h0c00 + word_in_block] !== 32'h94756123 + word_in_block)
                $fatal(1, "Dirty eviction mismatch at word %0d", word_in_block);
            eviction_checks <= eviction_checks + 1;
          end
          32'hf0000000: begin
            if (write_errors != 1 || eviction_checks != 1)
              $fatal(1, "Missing rejected write or dirty eviction");
`ifdef NGAGE_BLOCK_WRITEBACK
            if (native_blocks == 0) $fatal(1, "No native eviction block accepted");
`else
            if (native_blocks != 0) $fatal(1, "Unexpected native eviction block");
`endif
            check_wb_data();""")
    bench = edit(bench, "        ram_saved_data <= ram_wdata;", """        ram_saved_data <= ram_wdata;
        ram_saved_block <= ram_write && block_write;
        ram_saved_block_data <= block_data;
        if (ram_write && block_write && (ram_address[3:0] != 0 || ram_be != 4'hf))
          $fatal(1, "Misaligned or masked native write");""")
    bench = edit(bench, "            assoc_words <= assoc_words + 1;",
                 "            assoc_words <= assoc_words + (ram_saved_block ? 4 : 1);")
    bench = edit(bench, """          for (lane = 0; lane < 4; lane = lane + 1)
          if (ram_saved_be[lane]) ram[ram_index][lane*8+:8] <= ram_saved_data[lane*8+:8];""", """          if (ram_saved_block) begin
            native_blocks <= native_blocks + 1;
            for (lane = 0; lane < 4; lane = lane + 1)
              ram[ram_index+lane] <= ram_saved_block_data[lane*32+:32];
          end else begin
            for (lane = 0; lane < 4; lane = lane + 1)
              if (ram_saved_be[lane]) ram[ram_index][lane*8+:8] <= ram_saved_data[lane*8+:8];
          end""")
    bench = edit(bench, "\nendmodule", "\n`include \"wb_data_contract_observe.vh\"\nendmodule")
    (args.out / "contract.v").write_text(bench)


if __name__ == "__main__":
    main()
