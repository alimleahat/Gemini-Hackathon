module load_store_unit (
    // Clock and Reset
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

    localparam logic [1:0] TYPE_BYTE     = 2'b00;
    localparam logic [1:0] TYPE_HALFWORD = 2'b01;
    localparam logic [1:0] TYPE_WORD     = 2'b10;

    typedef enum logic [1:0] {
        ST_IDLE        = 2'b00,
        ST_WAIT_GNT    = 2'b01,
        ST_WAIT_RVALID = 2'b10
    } lsu_state_t;

    lsu_state_t  state;
    logic [31:0] eff_addr;
    logic [3:0]  calc_be;
    logic        addr_aligned;

    // Combinational effective address, alignment check, and byte-enable generation
    always_comb begin
        eff_addr     = ex_if_addr_base_i + ex_if_addr_offset_i;
        calc_be      = 4'b0000;
        addr_aligned = 1'b0;

        case (ex_if_type_i)
            TYPE_BYTE: begin
                addr_aligned = 1'b1;
                case (eff_addr[1:0])
                    2'b00: calc_be = 4'b0001;
                    2'b01: calc_be = 4'b0010;
                    2'b10: calc_be = 4'b0100;
                    2'b11: calc_be = 4'b1000;
                    default: calc_be = 4'b0000;
                endcase
            end

            TYPE_HALFWORD: begin
                case (eff_addr[1:0])
                    2'b00: begin
                        addr_aligned = 1'b1;
                        calc_be      = 4'b0011;
                    end
                    2'b10: begin
                        addr_aligned = 1'b1;
                        calc_be      = 4'b1100;
                    end
                    default: begin
                        addr_aligned = 1'b0;
                        calc_be      = 4'b0000;
                    end
                endcase
            end

            TYPE_WORD: begin
                if (eff_addr[1:0] == 2'b00) begin
                    addr_aligned = 1'b1;
                    calc_be      = 4'b1111;
                end else begin
                    addr_aligned = 1'b0;
                    calc_be      = 4'b0000;
                end
            end

            default: begin
                addr_aligned = 1'b0;
                calc_be      = 4'b0000;
            end
        endcase
    end

    // Sequential control and interface registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            ex_if_ready_o    <= 1'b1;
            dmem_req_o       <= 1'b0;
            dmem_req_we_o    <= 1'b0;
            dmem_req_addr_o  <= 32'd0;
            dmem_req_be_o    <= 4'd0;
            dmem_req_wdata_o <= 32'd0;
            wb_if_rvalid_o   <= 1'b0;
            wb_if_rdata_o    <= 32'd0;
        end else begin
            // Writeback valid is asserted for a single clock cycle per load completion
            wb_if_rvalid_o <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (ex_if_req_i && ex_if_ready_o && addr_aligned) begin
                        state            <= ST_WAIT_GNT;
                        ex_if_ready_o    <= 1'b0;
                        dmem_req_o       <= 1'b1;
                        dmem_req_we_o    <= ex_if_we_i;
                        dmem_req_addr_o  <= eff_addr;
                        dmem_req_be_o    <= calc_be;
                        dmem_req_wdata_o <= ex_if_we_i ? ex_if_wdata_i : 32'd0;
                    end
                end

                ST_WAIT_GNT: begin
                    if (dmem_gnt_i) begin
                        dmem_req_o       <= 1'b0;
                        dmem_req_we_o    <= 1'b0;
                        dmem_req_addr_o  <= 32'd0;
                        dmem_req_be_o    <= 4'd0;
                        dmem_req_wdata_o <= 32'd0;

                        if (dmem_req_we_o) begin
                            // Store completes upon grant
                            state         <= ST_IDLE;
                            ex_if_ready_o <= 1'b1;
                        end else if (dmem_rvalid_i) begin
                            // Load completes if rvalid arrives simultaneously
                            state          <= ST_IDLE;
                            ex_if_ready_o  <= 1'b1;
                            wb_if_rvalid_o <= 1'b1;
                            wb_if_rdata_o  <= dmem_rsp_rdata_i;
                        end else begin
                            state <= ST_WAIT_RVALID;
                        end
                    end
                end

                ST_WAIT_RVALID: begin
                    if (dmem_rvalid_i) begin
                        state          <= ST_IDLE;
                        ex_if_ready_o  <= 1'b1;
                        wb_if_rvalid_o <= 1'b1;
                        wb_if_rdata_o  <= dmem_rsp_rdata_i;
                    end
                end

                default: begin
                    state            <= ST_IDLE;
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
