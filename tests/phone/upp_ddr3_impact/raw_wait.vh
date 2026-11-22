    // Simulation-only blocking scalar bridge with 64-bit backing and
    // byte enables. Each selected command completes after the configured
    // additional clocks. Bulk zeroing accepts one 64-bit beat per clock.
    integer model_regions=0, model_reads=0, model_writes=0;
    integer model_waited=0;
    initial begin
        if ($value$plusargs("upp_regions=%d",model_regions)) begin end
        if ($value$plusargs("upp_read_extra=%d",model_reads)) begin end
        if ($value$plusargs("upp_write_extra=%d",model_writes)) begin end
    end
    wire model_selected = (model_regions[0] && upload_selected) ||
                          (model_regions[1] && nosmem_selected);
    wire model_access = req && init_done && model_selected && valid_lanes && !response_pending;
    wire model_ready = !model_access || model_waited >= (we ? model_writes : model_reads);
    wire [14:0] model_index = {nosmem_selected, a[15:2]};
    wire [15:0] model_clear_offset = {1'b0, init_index};
    wire model_clear_nos = model_regions[1] && (!model_regions[0] || model_clear_offset[13]);
    wire model_clear_active = (model_regions == 3 || (model_regions != 0 && !model_clear_offset[13]));
    wire [31:0] model_read_data;
    reg [63:0] model_mem [0:16383];
    integer model_byte;
    wire [63:0] model_pair = model_mem[model_index[14:1]];
    assign model_read_data = model_index[0] ? model_pair[63:32] : model_pair[31:0];
    always @(posedge clk) begin
        if (rst || !model_access || (local_access && local_ready))
            model_waited <= 0;
        else if (!model_ready)
            model_waited <= model_waited + 1;
        if (clearing && model_clear_active)
            model_mem[{model_clear_nos, model_clear_offset[12:0]}] <= 0;
        else if (model_access && local_access && local_ready && we)
            for (model_byte=0; model_byte<4; model_byte=model_byte+1)
                if (sel[model_byte])
                    model_mem[model_index[14:1]][(model_index[0] ? 32 : 0) + model_byte*8 +: 8] <= din[model_byte*8 +: 8];
    end
