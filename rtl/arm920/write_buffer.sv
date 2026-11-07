// SPDX-License-Identifier: GPL-3.0-or-later
// ARM920-shaped write buffer: four address entries, each carrying up to four
// consecutive words (16 words total). The caller supplies transaction groups
// in program order. It must not merge writes to device registers on its own.
// Buffered writes cannot generate architectural external aborts. An unexpected
// bus error is latched and the current beat retained for an explicit retry.
module arm920_write_buffer (
 input logic clk,reset,
 input logic push_valid,output logic push_ready,
 input logic [31:0] push_address,input logic [2:0] push_words,
 input logic [127:0] push_data,input logic [15:0] push_byte_enable,
 output logic empty,full,output logic [2:0] entries,
 input logic [31:0] query_line_address, output logic query_line_pending,
 output logic bus_valid,output logic [31:0] bus_address,bus_data,
 output logic [3:0] bus_byte_enable,
 input logic bus_ack,bus_error,
 output logic error_latched,input logic clear_error
);
 logic [31:0] addresses[0:3];
 logic [2:0] lengths[0:3];
 logic [127:0] data[0:3];
 logic [15:0] enables[0:3];
 logic [1:0] head,tail,word_index;
 logic [2:0] count;
 wire beat_done=bus_valid && bus_ack && !bus_error;
 wire group_done=beat_done && ({1'b0,word_index}+3'd1==lengths[head]);
 wire [1:0] last=tail-1'b1;
 // Adjacent single-word stores share one address slot but are still issued
 // as separate ordered bus beats. Never extend a group being retired now.
 wire merge_single=count!=0 && push_words==1 && lengths[last]<4 &&
                  push_address==addresses[last]+({29'b0,lengths[last]}<<2) &&
                  !(group_done && head==last);
 wire push=push_valid && push_ready;
 wire new_group=push && !merge_single;
 // Compare every queued word, including groups crossing a 32-byte line.
 // Retired words in the head group may cause a harmless conservative stall.
 // Compare physical slots in parallel. Rotating all addresses/lengths by
 // head before comparing puts a mux layer on the bus request critical path.
 wire [15:0] pending_words;
 genvar query_slot, query_word;
 generate
  for(query_slot=0;query_slot<4;query_slot=query_slot+1) begin : query_slots
   wire [1:0] distance_from_head = query_slot - head;
   for(query_word=0;query_word<4;query_word=query_word+1) begin : words
    assign pending_words[query_slot*4+query_word] =
     {1'b0,distance_from_head}<count && query_word<lengths[query_slot] &&
     ((addresses[query_slot]+32'(query_word*4)) >> 5)==(query_line_address >> 5);
   end
  end
 endgenerate
 assign query_line_pending=|pending_words;
 assign empty=count==0;assign full=count==4;assign entries=count;
 assign bus_valid=!empty && !error_latched;
 assign bus_address=addresses[head]+{28'b0,word_index,2'b0};
 assign bus_data=data[head][word_index*32+:32];
 assign bus_byte_enable=enables[head][word_index*4+:4];
 assign push_ready=!full || group_done || merge_single;
 always_ff @(posedge clk) begin
  if(reset)begin head<=0;tail<=0;count<=0;word_index<=0;error_latched<=0;end
  else begin
   if(clear_error) error_latched<=0;
   if(bus_valid && bus_error) error_latched<=1;
   if(new_group)begin
    addresses[tail]<=push_address;lengths[tail]<=push_words;
    data[tail]<=push_data;enables[tail]<=push_byte_enable;tail<=tail+1'b1;
   end else if(push)begin
    data[last][lengths[last]*32+:32]<=push_data[31:0];
    enables[last][lengths[last]*4+:4]<=push_byte_enable[3:0];
    lengths[last]<=lengths[last]+1'b1;
   end
   if(beat_done) begin
    if(group_done)begin head<=head+1'b1;word_index<=0;end
    else word_index<=word_index+1'b1;
   end
   case({new_group,group_done})
    2'b10:count<=count+1'b1;
    2'b01:count<=count-1'b1;
    default:;
   endcase
  end
 end
`ifndef SYNTHESIS
 always @(posedge clk) if(!reset && push && (push_words==0 || push_words>4))
  $fatal(1,"write buffer group must contain one to four words");
`endif
endmodule
