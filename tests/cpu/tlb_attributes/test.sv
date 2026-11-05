`timescale 1ns/1ps
`include "zap_defines.svh"
module test;
 parameter LPAGE_TLB_ENTRIES=8,SPAGE_TLB_ENTRIES=8,SECTION_TLB_ENTRIES=8,FPAGE_TLB_ENTRIES=8;
 reg clk=0,ce=1,mmu=1,rd=1,wr=0;
 reg [31:0] va=32'h00000120;
 reg [`ZAP_SPAGE_TLB_WDT-1:0] sm_entry=0;
 reg [`ZAP_LPAGE_TLB_WDT-1:0] lg_entry=0;
 reg [`ZAP_SECTION_TLB_WDT-1:0] section=0;
 reg [`ZAP_FPAGE_TLB_WDT-1:0] fine=0;
 reg [3:0] selected=0;
 reg [4:0] mode_bits=5'h13;reg [1:0] sr=0;reg [31:0] dac=0;
 wire walk,cacheable,bufferable;
 wire [7:0] fsr,external_fsr;wire [31:0] far,pa;
 always #5 clk=~clk;
 zap_tlb_check dut(.i_clk(clk),.i_clkena(ce),.i_mmu_en(mmu),.i_va(va),.i_rd(rd),.i_wr(wr),
  .i_cpsr(mode_bits),.i_sr(sr),.i_dac_reg(dac),
  .i_sptlb_rdata(sm_entry),.i_sptlb_rdav(selected[0]),
  .i_lptlb_rdata(lg_entry),.i_lptlb_rdav(selected[1]),
  .i_setlb_rdata(section),.i_setlb_rdav(selected[2]),
  .i_fptlb_rdata(fine),.i_fptlb_rdav(selected[3]),
  .o_walk(walk),.o_fsr(fsr),.o_external_fsr(external_fsr),.o_far(far),.o_bufferable(bufferable),.o_cacheable(cacheable),.o_phy_addr(pa));
 integer mode,cb,ap,srval,user,write_access,domain;
 reg allowed; reg [3:0] expected_fault;
 initial begin
  dac=32'hffffffff;
  sm_entry[1:0]=2;lg_entry[1:0]=1;section[1:0]=2;fine[1:0]=3;
  sm_entry[`ZAP_SPAGE_TLB__BASE]=20'habcde;
  lg_entry[`ZAP_LPAGE_TLB__BASE]=16'habcd;
  section[`ZAP_SECTION_TLB__BASE]=12'habc;
  fine[`ZAP_FPAGE_TLB__BASE]=22'h2af378;
  for(mode=0;mode<4;mode=mode+1) begin
   selected=1<<mode;
   for(cb=0;cb<4;cb=cb+1) begin
    sm_entry[`ZAP_SPAGE_TLB__CB]=cb; lg_entry[`ZAP_LPAGE_TLB__CB]=cb;
    section[`ZAP_SECTION_TLB__CB]=cb;fine[`ZAP_FPAGE_TLB__CB]=cb;
    @(posedge clk);#1;
    if ({cacheable,bufferable} !== cb[1:0] || fsr!==0 || walk!==0)
      $fatal(1,"mode=%0d C/B=%0d got %b%b fsr=%h walk=%b",mode,cb,cacheable,bufferable,fsr,walk);
   end
  end
  sm_entry[`ZAP_SPAGE_TLB__DAC_SEL]=4'h6;lg_entry[`ZAP_LPAGE_TLB__DAC_SEL]=4'h6;
  section[`ZAP_SECTION_TLB__DAC_SEL]=4'h6;fine[`ZAP_FPAGE_TLB__DAC_SEL]=4'h6;
  for(mode=0;mode<4;mode=mode+1) begin
   selected=1<<mode;@(posedge clk);#1;
   if(external_fsr !== (mode==2 ? 8'h68 : 8'h6a))$fatal(1,"external abort status mode=%0d got %h",mode,external_fsr);
  end
  // ARM920 TRM table 3-11: client permissions plus domain behavior.
  for(mode=0;mode<4;mode=mode+1) begin
   selected=1<<mode;
   for(domain=0;domain<4;domain=domain+1)
   for(ap=0;ap<4;ap=ap+1)
   for(srval=0;srval<3;srval=srval+1)
   for(user=0;user<2;user=user+1)
   for(write_access=0;write_access<2;write_access=write_access+1) begin
    dac=domain;sr=srval;mode_bits=user ? 5'h10 : 5'h13;rd=!write_access;wr=write_access;
    section[`ZAP_SECTION_TLB__DAC_SEL]=0;section[`ZAP_SECTION_TLB__AP]=ap;
    sm_entry[`ZAP_SPAGE_TLB__DAC_SEL]=0;sm_entry[`ZAP_SPAGE_TLB__AP]={4{ap[1:0]}};
    lg_entry[`ZAP_LPAGE_TLB__DAC_SEL]=0;lg_entry[`ZAP_LPAGE_TLB__AP]={4{ap[1:0]}};
    fine[`ZAP_FPAGE_TLB__DAC_SEL]=0;fine[`ZAP_FPAGE_TLB__AP]=ap;
    allowed=0;
    if(domain==3) allowed=1;
    else if(domain==1) case(ap)
      0: case(srval)
       1: allowed=!write_access;
       2: allowed=!user && !write_access;
       default: allowed=0;
      endcase
      1: allowed=!user;
      2: allowed=!user || !write_access;
      3: allowed=1;
    endcase
    if(allowed) expected_fault=0;
    else if(domain==1) expected_fault=(mode==2)?4'hd:4'hf;
    else expected_fault=(mode==2)?4'h9:4'hb;
    @(posedge clk);#1;
    if(fsr[3:0]!==expected_fault)
     $fatal(1,"mode=%0d domain=%0d AP=%0d SR=%0d user=%0d write=%0d got FSR=%h expected=%h",mode,domain,ap,srval,user,write_access,fsr,expected_fault);
   end
  end
  $display("PASS: domain and access permissions across page types");
  selected=0;mmu=0;@(posedge clk);#1;
  if (pa!==va || cacheable!==0 || bufferable!==0) $fatal(1,"MMU disabled outputs");
  $display("PASS: C/B attributes for all four translation types");$finish;
 end
endmodule
