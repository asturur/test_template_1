// D100 UPP chip boundary. The MiSTer instantiation includes the ARM and
// peripheral logic; external-bus mode is retained for focused board tests.
// Active bus, CBUS and ADSP ports are transaction-level migration interfaces,
// not the schematic's multiplexed electrical pin timings.
module ngage_upp #(parameter INTERNAL_CPU=0)(
 input wire clk,rst,init_rst,
 input wire ext_cyc,ext_stb,ext_we,ext_commit,input wire [31:0] ext_adr,ext_din,input wire [3:0] ext_sel,
 input wire cpu_ack,cpu_err,input wire [31:0] cpu_rdata,output wire cpu_lock,
 output wire bus_cyc,bus_stb,bus_we,bus_commit,output wire [31:0] bus_adr,bus_din,output wire [3:0] bus_sel,
 input wire cfg_lcd,cfg_keypad,cfg_clocks,dma_irq_pending,sim_fiq_pending,output wire dma_irq_clear,
 output wire claim,ready,unmodeled,irq,fiq,init_done,output wire [31:0] dout,
 output wire trace_valid,output wire [31:0] trace_addr,trace_data,output wire [3:0] trace_sel,
 input wire cbus_claim,cbus_bad,cbus_irq,input wire [31:0] cbus_data,
 input wire [15:0] route2a,route2c,route3b,input wire cbus8d_written,
 output wire uem_periodic,uem_irq_clear,
 input wire mdi_claim,mdi_bad,input wire [31:0] mdi_data,input wire [15:0] mdi_events,output wire adsp_tick
);
 generate if(INTERNAL_CPU)begin: cpu_inside
  ngage_cpu cpu(.clk(clk),.reset(rst),.irq(irq),.fiq(fiq),.wb_lock(cpu_lock),
   .wb_cyc(bus_cyc),.wb_stb(bus_stb),.wb_address(bus_adr),.wb_write(bus_we),
   .wb_write_data(bus_din),.wb_byte_enable(bus_sel),.wb_cycle_type(),.wb_burst_type(),
   .wb_ack(cpu_ack),.wb_read_data(cpu_rdata),.wb_error(cpu_err));
  assign bus_commit=cpu_ack;
 end else begin: external_master
  assign cpu_lock=1'b0;
  assign bus_cyc=ext_cyc;assign bus_stb=ext_stb;assign bus_we=ext_we;
  assign bus_adr=ext_adr;assign bus_din=ext_din;assign bus_sel=ext_sel;assign bus_commit=ext_commit;
 end endgenerate
 ngage_upp_peripherals peripherals(.rst(rst),.init_rst(init_rst),.clk(clk),.cyc(bus_cyc),.stb(bus_stb),
  .adr(bus_adr),.we(bus_we),.din(bus_din),.sel(bus_sel),.commit(bus_commit),.cfg_lcd(cfg_lcd),
  .cfg_keypad(cfg_keypad),.cfg_clocks(cfg_clocks),.dma_irq_pending(dma_irq_pending),
  .sim_fiq_pending(sim_fiq_pending),.dma_irq_clear(dma_irq_clear),.claim(claim),.ready(ready),
  .dout(dout),.unmodeled(unmodeled),.irq(irq),.fiq(fiq),.init_done(init_done),
  .trace_valid(trace_valid),.trace_addr(trace_addr),.trace_data(trace_data),.trace_sel(trace_sel),
  .cbus_claim(cbus_claim),.cbus_bad(cbus_bad),.cbus_irq(cbus_irq),.cbus_data(cbus_data),
  .route2a(route2a),.route2c(route2c),.route3b(route3b),.cbus8d_written(cbus8d_written),
  .uem_periodic(uem_periodic),.uem_irq_clear(uem_irq_clear),.mdi_claim(mdi_claim),
  .mdi_bad(mdi_bad),.mdi_data(mdi_data),.mdi_events(mdi_events),.adsp_tick(adsp_tick));
endmodule
