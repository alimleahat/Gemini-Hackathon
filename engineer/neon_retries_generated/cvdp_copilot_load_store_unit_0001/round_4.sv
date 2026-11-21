module load_store_unit (
    input  logic        clk,
    input  logic        rst_n,

    // Data-Cache Interface
    output logic        dmem_req_o,
    input  logic        dmem_gnt_i,
    output logic [31:0] dmem_req_addr_o,
    output logic        dmem_req_we_o,
    output logic [3:0]  dmem_req_be_o,
    output logic [31:0] dmem_req_wdata_o,
    input  logic        dmem_rvalid_i,
    input  logic [31:0] dmem_rsp_rdata_i,

    // Execution Stage Interface
    input  logic        ex_if_req_i,
    input  logic        ex_if_we_i,
    input  logic [1:0]  ex_if_type_i,
    input  logic [31:0] ex_if_wdata_i,
    input  logic [31:0] ex_if_addr_base_i,
    input  logic [31:0] ex_if_addr_offset_i,
    output logic        ex_if_ready_o,

    // Writeback Interface
    output logic [31:0] wb_if_rdata_o,
    output logic        wb_if_rvalid_o
);

    localparam [1:0] S_IDLE        = 2'b00;
    localparam [1:0] S_WAIT_GNT    = 2'b01;
    localparam [1:0] S_WAIT_RVALID = 2'b10;

    localparam [1:0] TYPE_BYTE     = 2'b00;
    localparam [1:0] TYPE_HALF     = 2'b01;
    localparam [1:0] TYPE_WORD     = 2'b10;

    logic [1:0]  state;
    logic [31:0] trans_addr;
    logic [3:0]  req_be;
    logic        addr_aligned;

    assign trans_addr = ex_if_addr_base_i + ex_if_addr_offset_i;

    always_comb begin
        req_be       = 4'b0000;
        addr_aligned = 1'b0;

        case (ex_if_type_i)
            TYPE_BYTE: begin
                case (trans_addr[1:0])
                    2'b00: begin
                        req_be       = 4'b0001;
                        addr_aligned = 1'b1;
                    end
                    2'b01: begin
                        req_be       = 4'b0010;
                        addr_aligned = 1'b1;
                    end
                    2'b10: begin
                        req_be       = 4'b0100;
                        addr_aligned = 1'b1;
                    end
                    2'b11: begin
                        req_be       = 4'b1000;
                        addr_aligned = 1'b1;
                    end
                    default: begin
                        req_be       = 4'b0000;
                        addr_aligned = 1'b0;
                    end
                endcase
            end

            TYPE_HALF: begin
                case (trans_addr[1:0])
                    2'b00: begin
                        req_be       = 4'b0011;
                        addr_aligned = 1'b1;
                    end
                    2'b10: begin
                        req_be       = 4'b1100;
                        addr_aligned = 1'b1;
                    end
                    default: begin
                        req_be       = 4'b0000;
                        addr_aligned = 1'b0;
                    end
                endcase
            end

            TYPE_WORD: begin
                if (trans_addr[1:0] == 2'b00) begin
                    req_be       = 4'b1111;
                    addr_aligned = 1'b1;
                end
            end

            default: begin
                req_be       = 4'b0000;
                addr_aligned = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            ex_if_ready_o    <= 1'b1;
            dmem_req_o       <= 1'b0;
            dmem_req_we_o    <= 1'b0;
            dmem_req_addr_o  <= 32'b0;
            dmem_req_be_o    <= 4'b0;
            dmem_req_wdata_o <= 32'b0;
            wb_if_rvalid_o   <= 1'b0;
            wb_if_rdata_o    <= 32'b0;
        end else begin
            wb_if_rvalid_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (ex_if_req_i && ex_if_ready_o && addr_aligned) begin
                        ex_if_ready_o    <= 1'b0;
                        dmem_req_o       <= 1'b1;
                        dmem_req_we_o    <= ex_if_we_i;
                        dmem_req_addr_o  <= trans_addr;
                        dmem_req_be_o    <= req_be;
                        dmem_req_wdata_o <= ex_if_we_i ? ex_if_wdata_i : 32'b0;
                        state            <= S_WAIT_GNT;
                    end
                end

                S_WAIT_GNT: begin
                    if (dmem_gnt_i) begin
                        dmem_req_o       <= 1'b0;
                        dmem_req_we_o    <= 1'b0;
                        dmem_req_addr_o  <= 32'b0;
                        dmem_req_be_o    <= 4'b0;
                        dmem_req_wdata_o <= 32'b0;

                        if (dmem_req_we_o) begin
                            ex_if_ready_o <= 1'b1;
                            state         <= S_IDLE;
                        end else begin
                            state         <= S_WAIT_RVALID;
                        end
                    end
                end

                S_WAIT_RVALID: begin
                    if (dmem_rvalid_i) begin
                        wb_if_rvalid_o <= 1'b1;
                        wb_if_rdata_o  <= dmem_rsp_rdata_i;
                        ex_if_ready_o  <= 1'b1;
                        state          <= S_IDLE;
                    end
                end

                default: begin
                    state            <= S_IDLE;
                    ex_if_ready_o    <= 1'b1;
                    dmem_req_o       <= 1'b0;
                    dmem_req_we_o    <= 1'b0;
                    dmem_req_addr_o  <= 32'b0;
                    dmem_req_be_o    <= 4'b0;
                    dmem_req_wdata_o <= 32'b0;
                end
            endcase
        end
    end

endmodule
