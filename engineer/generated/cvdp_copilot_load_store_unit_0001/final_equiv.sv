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

    localparam logic [1:0] STATE_IDLE        = 2'd0;
    localparam logic [1:0] STATE_WAIT_GNT    = 2'd1;
    localparam logic [1:0] STATE_WAIT_RVALID = 2'd2;

    localparam logic [1:0] TYPE_BYTE     = 2'b00;
    localparam logic [1:0] TYPE_HALFWORD = 2'b01;
    localparam logic [1:0] TYPE_WORD     = 2'b10;

    logic [1:0]  state;
    logic [31:0] eff_addr;
    logic [3:0]  req_be;
    logic        access_aligned;

    assign eff_addr = ex_if_addr_base_i + ex_if_addr_offset_i;

    always_comb begin
        req_be         = 4'b0000;
        access_aligned = 1'b0;

        case (ex_if_type_i)
            TYPE_BYTE: begin
                access_aligned = 1'b1;
                case (eff_addr[1:0])
                    2'b00:   req_be = 4'b0001;
                    2'b01:   req_be = 4'b0010;
                    2'b10:   req_be = 4'b0100;
                    2'b11:   req_be = 4'b1000;
                    default: req_be = 4'b0000;
                endcase
            end

            TYPE_HALFWORD: begin
                case (eff_addr[1:0])
                    2'b00: begin
                        access_aligned = 1'b1;
                        req_be         = 4'b0011;
                    end
                    2'b10: begin
                        access_aligned = 1'b1;
                        req_be         = 4'b1100;
                    end
                    default: begin
                        access_aligned = 1'b0;
                        req_be         = 4'b0000;
                    end
                endcase
            end

            TYPE_WORD: begin
                if (eff_addr[1:0] == 2'b00) begin
                    access_aligned = 1'b1;
                    req_be         = 4'b1111;
                end
            end

            default: begin
                access_aligned = 1'b0;
                req_be         = 4'b0000;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= STATE_IDLE;
            ex_if_ready_o    <= 1'b1;
            dmem_req_o       <= 1'b0;
            dmem_req_we_o    <= 1'b0;
            dmem_req_addr_o  <= 32'd0;
            dmem_req_be_o    <= 4'd0;
            dmem_req_wdata_o <= 32'd0;
            wb_if_rvalid_o   <= 1'b0;
            wb_if_rdata_o    <= 32'd0;
        end else begin
            wb_if_rvalid_o <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (ex_if_req_i && ex_if_ready_o && access_aligned) begin
                        dmem_req_o       <= 1'b1;
                        dmem_req_addr_o  <= eff_addr;
                        dmem_req_we_o    <= ex_if_we_i;
                        dmem_req_be_o    <= req_be;
                        dmem_req_wdata_o <= ex_if_we_i ? ex_if_wdata_i : 32'd0;
                        ex_if_ready_o    <= 1'b0;
                        state            <= STATE_WAIT_GNT;
                    end
                end

                STATE_WAIT_GNT: begin
                    if (dmem_gnt_i) begin
                        dmem_req_o       <= 1'b0;
                        dmem_req_we_o    <= 1'b0;
                        dmem_req_addr_o  <= 32'd0;
                        dmem_req_be_o    <= 4'd0;
                        dmem_req_wdata_o <= 32'd0;

                        if (dmem_req_we_o) begin
                            ex_if_ready_o <= 1'b1;
                            state         <= STATE_IDLE;
                        end else begin
                            state         <= STATE_WAIT_RVALID;
                        end
                    end
                end

                STATE_WAIT_RVALID: begin
                    if (dmem_rvalid_i) begin
                        wb_if_rvalid_o <= 1'b1;
                        wb_if_rdata_o  <= dmem_rsp_rdata_i;
                        ex_if_ready_o  <= 1'b1;
                        state          <= STATE_IDLE;
                    end
                end

                default: begin
                    state            <= STATE_IDLE;
                    ex_if_ready_o    <= 1'b1;
                    dmem_req_o       <= 1'b0;
                    dmem_req_we_o    <= 1'b0;
                    dmem_req_addr_o  <= 32'd0;
                    dmem_req_be_o    <= 4'd0;
                    dmem_req_wdata_o <= 32'd0;
                end
            endcase
        end
    end

endmodule

