module load_store_unit (
    input  logic        clk,
    input  logic        rst_n,

    output logic        dmem_req_o,
    input  logic        dmem_gnt_i,
    output logic [31:0] dmem_req_addr_o,
    output logic        dmem_req_we_o,
    output logic [3:0]  dmem_req_be_o,
    output logic [31:0] dmem_req_wdata_o,
    input  logic        dmem_rvalid_i,
    input  logic [31:0] dmem_rsp_rdata_i,

    input  logic        ex_if_req_i,
    input  logic        ex_if_we_i,
    input  logic [1:0]  ex_if_type_i,
    input  logic [31:0] ex_if_wdata_i,
    input  logic [31:0] ex_if_addr_base_i,
    input  logic [31:0] ex_if_addr_offset_i,
    output logic        ex_if_ready_o,

    output logic [31:0] wb_if_rdata_o,
    output logic        wb_if_rvalid_o
);

    logic [31:0] eff_addr;
    logic        access_aligned;
    logic        accept;
    logic        load_done;

    logic [31:0] addr_q;
    logic [31:0] wdata_q;
    logic [1:0]  req_type_q;

    assign eff_addr = ex_if_addr_base_i + ex_if_addr_offset_i;

    assign access_aligned = (~ex_if_type_i[1] & ~ex_if_type_i[0]) |
                            (~ex_if_type_i[1] &  ex_if_type_i[0] & ~eff_addr[0]) |
                            ( ex_if_type_i[1] & ~ex_if_type_i[0] & ~eff_addr[1] & ~eff_addr[0]);

    assign accept    = ex_if_ready_o & ex_if_req_i & access_aligned;
    assign load_done = ~ex_if_ready_o & ~dmem_req_o & dmem_rvalid_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_if_ready_o  <= 1'b1;
            dmem_req_o     <= 1'b0;
            dmem_req_we_o  <= 1'b0;
            wb_if_rvalid_o <= 1'b0;
            req_type_q     <= 2'b00;
            addr_q         <= 32'd0;
            wdata_q        <= 32'd0;
            wb_if_rdata_o  <= 32'd0;
        end else begin
            ex_if_ready_o  <= (ex_if_ready_o & ~accept) | (dmem_req_we_o & dmem_gnt_i) | load_done;
            wb_if_rvalid_o <= load_done;

            if (accept) begin
                dmem_req_o    <= 1'b1;
                dmem_req_we_o <= ex_if_we_i;
                req_type_q    <= ex_if_type_i;
                addr_q        <= eff_addr;
                wdata_q       <= ex_if_wdata_i;
            end else if (dmem_gnt_i) begin
                dmem_req_o    <= 1'b0;
                dmem_req_we_o <= 1'b0;
            end

            if (load_done) begin
                wb_if_rdata_o <= dmem_rsp_rdata_i;
            end
        end
    end

    assign dmem_req_addr_o  = dmem_req_o    ? addr_q  : 32'd0;
    assign dmem_req_wdata_o = dmem_req_we_o ? wdata_q : 32'd0;

    assign dmem_req_be_o[0] = dmem_req_o ? (~addr_q[1] & ~addr_q[0]) : 1'b0;
    assign dmem_req_be_o[1] = dmem_req_o ? (~addr_q[1] & (addr_q[0] | req_type_q[0] | req_type_q[1])) : 1'b0;
    assign dmem_req_be_o[2] = dmem_req_o ? (req_type_q[1] | (addr_q[1] & ~addr_q[0])) : 1'b0;
    assign dmem_req_be_o[3] = dmem_req_o ? (req_type_q[1] | (addr_q[1] & (addr_q[0] | req_type_q[0]))) : 1'b0;

endmodule
