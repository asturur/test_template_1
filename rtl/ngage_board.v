// Phone board transaction-level composition. UPP external pin buses are not
// yet bit-accurate; temporary CBUS/ADSP transactions are explicitly named.
module ngage_board #(parameter INTERNAL_CPU=0)(
    input  wire        rst,
    input  wire        init_rst,
    input  wire        clk,
    // CPU wishbone request (held stable while pending)
    input  wire        cyc,
    input  wire        stb,
    input  wire [31:0] adr,
    input  wire        we,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    input  wire        commit,      // harness acknowledges this cycle
    // configuration (from the harness command line)
    input  wire        cfg_lcd,     // lcd-probe option
    input  wire        cfg_keypad,  // keypad-gpio option
    input  wire        cfg_clocks,  // ideal-clocks option
    input  wire        dma_irq_pending, sim_fiq_pending,
    output wire        dma_irq_clear,
    // service
    output wire        claim,
    output wire        ready,       // dout valid / access may be acknowledged
    output wire [31:0] dout,
    output wire        unmodeled,
    output wire        irq,
    output wire        fiq,
    output wire        init_done,
    output wire        trace_valid,
    output wire [31:0] trace_addr,trace_data,
    output wire [3:0]  trace_sel,
    // Internal-CPU mode is used by the MiSTer top. External mode preserves
    // the transaction interface used by focused board tests.
    input wire cpu_ack,cpu_err,input wire [31:0] cpu_rdata,output wire cpu_lock,
    output wire bus_cyc,bus_stb,bus_we,output wire [31:0] bus_adr,bus_din,output wire [3:0] bus_sel
);
wire cbus_claim,cbus_bad,cbus_irq,uem_periodic,uem_irq_clear,cbus8d_written;
wire [31:0] cbus_data,mdi_data;
wire [15:0] route2a,route2c,route3b,mdi_events;
wire mdi_claim,mdi_bad,adsp_tick;
wire [31:0] aligned_addr={bus_adr[31:2],2'b00};
wire bus_commit;
ngage_upp #(.INTERNAL_CPU(INTERNAL_CPU)) upp(.rst(rst),.init_rst(init_rst),.clk(clk),
 .ext_cyc(cyc),.ext_stb(stb),.ext_adr(adr),.ext_we(we),.ext_din(din),.ext_sel(sel),.ext_commit(commit),
 .cpu_ack(cpu_ack),.cpu_err(cpu_err),.cpu_rdata(cpu_rdata),.cpu_lock(cpu_lock),
 .bus_cyc(bus_cyc),.bus_stb(bus_stb),.bus_adr(bus_adr),.bus_we(bus_we),.bus_din(bus_din),.bus_sel(bus_sel),.bus_commit(bus_commit),
 .cfg_lcd(cfg_lcd),
 .cfg_keypad(cfg_keypad),.cfg_clocks(cfg_clocks),.dma_irq_pending(dma_irq_pending),
 .sim_fiq_pending(sim_fiq_pending),.dma_irq_clear(dma_irq_clear),.claim(claim),.ready(ready),
 .dout(dout),.unmodeled(unmodeled),.irq(irq),.fiq(fiq),.init_done(init_done),
 .trace_valid(trace_valid),.trace_addr(trace_addr),.trace_data(trace_data),.trace_sel(trace_sel),
 .cbus_claim(cbus_claim),.cbus_bad(cbus_bad),.cbus_irq(cbus_irq),.cbus_data(cbus_data),
 .route2a(route2a),.route2c(route2c),.route3b(route3b),.cbus8d_written(cbus8d_written),
 .uem_periodic(uem_periodic),.uem_irq_clear(uem_irq_clear),.mdi_claim(mdi_claim),
 .mdi_bad(mdi_bad),.mdi_data(mdi_data),.mdi_events(mdi_events),.adsp_tick(adsp_tick));
ngage_uem uem(.clk(clk),.reset(rst),.req(bus_cyc && bus_stb),.commit(bus_commit),.we(bus_we),
 .addr(aligned_addr),.din(bus_din),.sel(bus_sel),.kernel_periodic(uem_periodic),.clear_irq(uem_irq_clear),
 .claim(cbus_claim),.bad(cbus_bad),.dout(cbus_data),.uem_int(cbus_irq),
 .route2a(route2a),.route2c(route2c),.route3b(route3b),.cbus8d_written(cbus8d_written));
ngage_adsp adsp(.clk(clk),.reset(rst),.tick(adsp_tick),.periodic_active(1'b1),
 .req(bus_cyc && bus_stb),.commit(bus_commit),.we(bus_we),.addr(aligned_addr),.din(bus_din),.sel(bus_sel),
 .claim(mdi_claim),.bad(mdi_bad),.dout(mdi_data),.irq_events(mdi_events));
// Physical radio components are explicitly unimplemented and disconnected.
// A future pin-accurate controller must replace these disabled connections.
ngage_lrb2 lrb2(.resetx(1'b0),.sleepx(1'b0),.sysclk(1'b0),.slpclk(1'b0),
 .cbusclk(1'b0),.cenx(1'b1),.cbusdata_i(1'b0),.cbusdata_o(),.cbusdata_oe(),
 .gpp_i(4'b0),.gpp_o(),.gpp_oe(),.model_implemented());
ngage_mjoelner gsm_rf(.resetx(1'b0),.rfbusclk(1'b0),.rfbusenx(1'b1),
 .rfbusda_i(1'b0),.rfbusda_o(),.rfbusda_oe(),.model_implemented());
endmodule
