// Simulation-only temporal checks of ALU instruction ownership and BTB writes.
`define BC dut.u_zap.u_zap_core
reg feedback_expected = 0;
reg [1023:0] predictor_expected;
integer owner_checks = 0, owner_bubbles = 0, owner_failed = 0, owner_held = 0;
always @(posedge clk) begin
  predictor_expected = `BC.u_zap_writeback.u_zap_btb.dav;
  if (`BC.reset || `BC.predecode_clear_btb) predictor_expected = 0;
  else if (`BC.u_zap_writeback.i_alu_feedback_valid)
    predictor_expected[`BC.u_zap_writeback.u_zap_btb.mem_wr_addr] =
            `BC.confirm_from_alu || `BC.clear_from_alu;
  if (`BC.u_zap_writeback.u_zap_btb.mem_wr_en &&
        (!`BC.alu_feedback_valid_ff || `BC.data_stall ||
         `BC.clear_from_writeback || (|`BC.owned_data_fault)))
    $fatal(1, "unowned or held BTB RAM write");
  if (`BC.u_zap_writeback.u_zap_btb.mem_wr_en && `BC.confirm_from_alu &&
        `BC.u_zap_writeback.u_zap_btb.mem_wr_data.target !==
            `BC.u_zap_alu_main.w_pc_from_alu_btarget)
    $fatal(1, "confirmed branch lost its actual BTB target");
  if (`BC.reset || `BC.clear_from_writeback) feedback_expected = 0;
  else if (((|`BC.owned_data_fault) || `BC.u_zap_alu_main.sleep_ff) && !`BC.data_stall)
    feedback_expected = 0;
  else if (`BC.clear_from_alu && !`BC.data_stall) feedback_expected = 0;
  else if (!`BC.data_stall)
    feedback_expected = `BC.shifter_condition_code_ff != 4'hf &&
            !`BC.shifter_irq_ff && !`BC.shifter_fiq_ff && !`BC.shifter_abt_ff;
  if (!`BC.reset) begin
    owner_checks = owner_checks + 1;
    if (!`BC.alu_feedback_valid_ff) owner_bubbles = owner_bubbles + 1;
    if (`BC.alu_feedback_valid_ff && !`BC.alu_dav_ff) owner_failed = owner_failed + 1;
    if (`BC.alu_feedback_valid_ff && `BC.data_stall) owner_held = owner_held + 1;
  end
  #1;
  if (`BC.alu_feedback_valid_ff !== feedback_expected)
    $fatal(1, "ALU feedback ownership differs from decoded instruction");
  if (`BC.u_zap_writeback.u_zap_btb.dav !== predictor_expected)
    $fatal(1, "BTB entry changed without accepted instruction feedback");
end
final begin
  $display("BRANCH_OWNER checks=%0d bubbles=%0d failed_condition=%0d held=%0d", owner_checks,
           owner_bubbles, owner_failed, owner_held);
end
`undef BC
