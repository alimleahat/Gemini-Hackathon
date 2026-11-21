module axi_register #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  logic                      clk_i,
    input  logic                      rst_n_i,
    input  logic [ADDR_WIDTH-1:0]     awaddr_i,
    input  logic                      awvalid_i,
    input  logic [DATA_WIDTH-1:0]     wdata_i,
    input  logic                      wvalid_i,
    input  logic [(DATA_WIDTH/8)-1:0] wstrb_i,
    input  logic                      bready_i,
    input  logic [ADDR_WIDTH-1:0]     araddr_i,
    input  logic                      arvalid_i,
    input  logic                      rready_i,
    input  logic                      done_i,

    output logic                      awready_o,
    output logic                      wready_o,
    output logic [1:0]                bresp_o,
    output logic                      bvalid_o,
    output logic                      arready_o,
    output logic [DATA_WIDTH-1:0]     rdata_o,
    output logic                      rvalid_o,
    output logic [1:0]                rresp_o,
    output logic [19:0]               beat_o,
    output logic                      start_o,
    output logic                      writeback_o
);

    // Register offsets (lower 12 bits)
    localparam logic [11:0] ADDR_BEAT      = 12'h100;
    localparam logic [11:0] ADDR_START     = 12'h200;
    localparam logic [11:0] ADDR_DONE      = 12'h300;
    localparam logic [11:0] ADDR_WRITEBACK = 12'h400;
    localparam logic [11:0] ADDR_ID        = 12'h500;

    // Fixed identification value
    localparam logic [31:0] ID_VALUE       = 32'h0001_0001;

    // AXI4-Lite response codes
    localparam logic [1:0]  RESP_OKAY      = 2'b00;
    localparam logic [1:0]  RESP_SLVERR    = 2'b10;

    // Write FSM states
    localparam logic [1:0]  W_ADDR         = 2'd0;
    localparam logic [1:0]  W_DATA         = 2'd1;
    localparam logic [1:0]  W_RESP         = 2'd2;

    // Read FSM states
    localparam logic        R_ADDR         = 1'b0;
    localparam logic        R_DATA         = 1'b1;

    logic [1:0]             w_state;
    logic                   r_state;
    logic [11:0]            awaddr_reg;
    logic                   done_reg;
    logic                   done_d;

    // Width-extended helpers for clean parameterization across any DATA_WIDTH >= 8
    wire [DATA_WIDTH+31:0]  wdata_ext      = {{32{1'b0}}, wdata_i};
    wire                    full_write     = &wstrb_i;
    wire                    done_rise      = done_i & ~done_d;
    wire                    done_status    = done_reg | done_rise;

    wire [DATA_WIDTH+31:0]  rdata_beat_ext = {{(DATA_WIDTH+12){1'b0}}, beat_o};
    wire [DATA_WIDTH+31:0]  rdata_strt_ext = {{(DATA_WIDTH+31){1'b0}}, start_o};
    wire [DATA_WIDTH+31:0]  rdata_done_ext = {{(DATA_WIDTH+31){1'b0}}, done_status};
    wire [DATA_WIDTH+31:0]  rdata_wb_ext   = {{(DATA_WIDTH+31){1'b0}}, writeback_o};
    wire [DATA_WIDTH+31:0]  rdata_id_ext   = {{DATA_WIDTH{1'b0}}, ID_VALUE};

    // Write channel FSM and register update logic
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            w_state     <= W_ADDR;
            awready_o   <= 1'b0;
            wready_o    <= 1'b0;
            bvalid_o    <= 1'b0;
            bresp_o     <= RESP_OKAY;
            awaddr_reg  <= 12'd0;
            beat_o      <= 20'd0;
            start_o     <= 1'b0;
            writeback_o <= 1'b0;
            done_reg    <= 1'b0;
            done_d      <= 1'b0;
        end else begin
            done_d <= done_i;
            if (done_rise) begin
                done_reg <= 1'b1;
            end

            case (w_state)
                W_ADDR: begin
                    if (awvalid_i && awready_o) begin
                        awready_o  <= 1'b0;
                        wready_o   <= 1'b1;
                        awaddr_reg <= awaddr_i[11:0];
                        w_state    <= W_DATA;
                    end else begin
                        awready_o  <= 1'b1;
                    end
                end

                W_DATA: begin
                    if (wvalid_i && wready_o) begin
                        wready_o <= 1'b0;
                        bvalid_o <= 1'b1;
                        w_state  <= W_RESP;

                        case (awaddr_reg)
                            ADDR_BEAT: begin
                                bresp_o <= RESP_OKAY;
                                if (full_write) begin
                                    beat_o <= wdata_ext[19:0];
                                end
                            end

                            ADDR_START: begin
                                bresp_o <= RESP_OKAY;
                                if (full_write && wstrb_i[0]) begin
                                    start_o <= wdata_i[0];
                                end
                            end

                            ADDR_DONE: begin
                                bresp_o <= RESP_OKAY;
                                if (full_write && wdata_i[0] && !done_rise) begin
                                    done_reg <= 1'b0;
                                end
                            end

                            ADDR_WRITEBACK: begin
                                bresp_o <= RESP_OKAY;
                                if (full_write && wstrb_i[0]) begin
                                    writeback_o <= wdata_i[0];
                                end
                            end

                            ADDR_ID: begin
                                bresp_o <= RESP_SLVERR;
                            end

                            default: begin
                                bresp_o <= RESP_SLVERR;
                            end
                        endcase
                    end
                end

                W_RESP: begin
                    if (bready_i && bvalid_o) begin
                        bvalid_o  <= 1'b0;
                        awready_o <= 1'b1;
                        w_state   <= W_ADDR;
                    end
                end

                default: begin
                    w_state   <= W_ADDR;
                    awready_o <= 1'b0;
                    wready_o  <= 1'b0;
                    bvalid_o  <= 1'b0;
                end
            endcase
        end
    end

    // Read channel FSM and address decode logic
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            r_state   <= R_ADDR;
            arready_o <= 1'b0;
            rvalid_o  <= 1'b0;
            rdata_o   <= '0;
            rresp_o   <= RESP_OKAY;
        end else begin
            case (r_state)
                R_ADDR: begin
                    if (arvalid_i && arready_o) begin
                        arready_o <= 1'b0;
                        rvalid_o  <= 1'b1;
                        r_state   <= R_DATA;

                        case (araddr_i[11:0])
                            ADDR_BEAT: begin
                                rdata_o <= rdata_beat_ext[DATA_WIDTH-1:0];
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_START: begin
                                rdata_o <= rdata_strt_ext[DATA_WIDTH-1:0];
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_DONE: begin
                                rdata_o <= rdata_done_ext[DATA_WIDTH-1:0];
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_WRITEBACK: begin
                                rdata_o <= rdata_wb_ext[DATA_WIDTH-1:0];
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_ID: begin
                                rdata_o <= rdata_id_ext[DATA_WIDTH-1:0];
                                rresp_o <= RESP_OKAY;
                            end

                            default: begin
                                rdata_o <= '0;
                                rresp_o <= RESP_SLVERR;
                            end
                        endcase
                    end else begin
                        arready_o <= 1'b1;
                    end
                end

                R_DATA: begin
                    if (rready_i && rvalid_o) begin
                        rvalid_o  <= 1'b0;
                        arready_o <= 1'b1;
                        r_state   <= R_ADDR;
                    end
                end
            endcase
        end
    end

endmodule
