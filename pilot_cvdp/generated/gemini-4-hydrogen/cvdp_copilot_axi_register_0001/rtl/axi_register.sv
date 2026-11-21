module axi_register #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input  logic                      clk_i,
    input  logic                      rst_n_i,

    // AXI4-Lite Write Address Channel
    input  logic [ADDR_WIDTH-1:0]     awaddr_i,
    input  logic                      awvalid_i,
    output logic                      awready_o,

    // AXI4-Lite Write Data Channel
    input  logic [DATA_WIDTH-1:0]     wdata_i,
    input  logic [(DATA_WIDTH/8)-1:0] wstrb_i,
    input  logic                      wvalid_i,
    output logic                      wready_o,

    // AXI4-Lite Write Response Channel
    output logic [1:0]                bresp_o,
    output logic                      bvalid_o,
    input  logic                      bready_i,

    // AXI4-Lite Read Address Channel
    input  logic [ADDR_WIDTH-1:0]     araddr_i,
    input  logic                      arvalid_i,
    output logic                      arready_o,

    // AXI4-Lite Read Data Channel
    output logic [DATA_WIDTH-1:0]     rdata_o,
    output logic [1:0]                rresp_o,
    output logic                      rvalid_o,
    input  logic                      rready_i,

    // Hardware Control & Status Interface
    input  logic                      done_i,
    output logic [19:0]               beat_o,
    output logic                      start_o,
    output logic                      writeback_o
);

    localparam logic [11:0] ADDR_BEAT      = 12'h100;
    localparam logic [11:0] ADDR_START     = 12'h200;
    localparam logic [11:0] ADDR_DONE      = 12'h300;
    localparam logic [11:0] ADDR_WRITEBACK = 12'h400;
    localparam logic [11:0] ADDR_ID        = 12'h500;

    localparam logic [31:0] ID_VALUE       = 32'h0001_0001;

    localparam logic [1:0]  RESP_OKAY      = 2'b00;
    localparam logic [1:0]  RESP_SLVERR    = 2'b10;

    localparam logic [1:0]  W_IDLE         = 2'd0;
    localparam logic [1:0]  W_DATA         = 2'd1;
    localparam logic [1:0]  W_RESP         = 2'd2;

    localparam logic [0:0]  R_IDLE         = 1'd0;
    localparam logic [0:0]  R_DATA         = 1'd1;

    logic [1:0]  w_state;
    logic [0:0]  r_state;
    logic [11:0] awaddr_reg;

    logic [19:0] beat_reg;
    logic        start_reg;
    logic        done_reg;
    logic        done_i_d;
    logic        writeback_reg;

    logic        full_strb;
    logic        done_rising;
    logic        done_status;

    logic [19:0]             beat_wdata;
    logic [DATA_WIDTH-1:0]   beat_rdata;
    logic [DATA_WIDTH-1:0]   id_rdata;
    logic [DATA_WIDTH-1:0]   start_rdata;
    logic [DATA_WIDTH-1:0]   done_rdata;
    logic [DATA_WIDTH-1:0]   wb_rdata;

    assign full_strb   = &wstrb_i;
    assign done_rising = done_i & ~done_i_d;
    assign done_status = done_reg | done_rising;

    assign beat_o      = beat_reg;
    assign start_o     = start_reg;
    assign writeback_o = writeback_reg;

    generate
        if (DATA_WIDTH >= 20) begin : g_wbeat_ge
            assign beat_wdata = wdata_i[19:0];
        end else begin : g_wbeat_lt
            assign beat_wdata = {{(20 - DATA_WIDTH){1'b0}}, wdata_i};
        end

        if (DATA_WIDTH > 20) begin : g_rbeat_gt
            assign beat_rdata = {{(DATA_WIDTH - 20){1'b0}}, beat_reg};
        end else begin : g_rbeat_le
            assign beat_rdata = beat_reg[DATA_WIDTH-1:0];
        end

        if (DATA_WIDTH > 32) begin : g_rid_gt
            assign id_rdata = {{(DATA_WIDTH - 32){1'b0}}, ID_VALUE};
        end else begin : g_rid_le
            assign id_rdata = ID_VALUE[DATA_WIDTH-1:0];
        end

        if (DATA_WIDTH > 1) begin : g_rbit_gt
            assign start_rdata = {{(DATA_WIDTH - 1){1'b0}}, start_reg};
            assign done_rdata  = {{(DATA_WIDTH - 1){1'b0}}, done_status};
            assign wb_rdata    = {{(DATA_WIDTH - 1){1'b0}}, writeback_reg};
        end else begin : g_rbit_le
            assign start_rdata = start_reg;
            assign done_rdata  = done_status;
            assign wb_rdata    = writeback_reg;
        end
    endgenerate

    // Write Transaction FSM and Register Updates
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            w_state       <= W_IDLE;
            awready_o     <= 1'b0;
            wready_o      <= 1'b0;
            bvalid_o      <= 1'b0;
            bresp_o       <= RESP_OKAY;
            awaddr_reg    <= 12'd0;
            beat_reg      <= 20'd0;
            start_reg     <= 1'b0;
            done_reg      <= 1'b0;
            done_i_d      <= 1'b0;
            writeback_reg <= 1'b0;
        end else begin
            done_i_d <= done_i;

            if (done_rising) begin
                done_reg <= 1'b1;
            end

            case (w_state)
                W_IDLE: begin
                    wready_o <= 1'b0;
                    bvalid_o <= 1'b0;
                    if (awvalid_i && awready_o) begin
                        awaddr_reg <= awaddr_i[11:0];
                        awready_o  <= 1'b0;
                        wready_o   <= 1'b1;
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
                                if (full_strb) begin
                                    beat_reg <= beat_wdata;
                                end
                            end

                            ADDR_START: begin
                                bresp_o <= RESP_OKAY;
                                if (full_strb) begin
                                    start_reg <= wdata_i[0];
                                end
                            end

                            ADDR_DONE: begin
                                bresp_o <= RESP_OKAY;
                                if (full_strb && wdata_i[0]) begin
                                    done_reg <= 1'b0;
                                end
                            end

                            ADDR_WRITEBACK: begin
                                bresp_o <= RESP_OKAY;
                                if (full_strb) begin
                                    writeback_reg <= wdata_i[0];
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
                    if (bvalid_o && bready_i) begin
                        bvalid_o  <= 1'b0;
                        bresp_o   <= RESP_OKAY;
                        awready_o <= 1'b1;
                        w_state   <= W_IDLE;
                    end
                end

                default: begin
                    w_state   <= W_IDLE;
                    awready_o <= 1'b1;
                    wready_o  <= 1'b0;
                    bvalid_o  <= 1'b0;
                    bresp_o   <= RESP_OKAY;
                end
            endcase
        end
    end

    // Read Transaction FSM
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            r_state   <= R_IDLE;
            arready_o <= 1'b0;
            rvalid_o  <= 1'b0;
            rresp_o   <= RESP_OKAY;
            rdata_o   <= {DATA_WIDTH{1'b0}};
        end else begin
            case (r_state)
                R_IDLE: begin
                    rvalid_o <= 1'b0;
                    if (arvalid_i && arready_o) begin
                        arready_o <= 1'b0;
                        rvalid_o  <= 1'b1;
                        r_state   <= R_DATA;

                        case (araddr_i[11:0])
                            ADDR_BEAT: begin
                                rdata_o <= beat_rdata;
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_START: begin
                                rdata_o <= start_rdata;
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_DONE: begin
                                rdata_o <= done_rdata;
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_WRITEBACK: begin
                                rdata_o <= wb_rdata;
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_ID: begin
                                rdata_o <= id_rdata;
                                rresp_o <= RESP_OKAY;
                            end

                            default: begin
                                rdata_o <= {DATA_WIDTH{1'b0}};
                                rresp_o <= RESP_SLVERR;
                            end
                        endcase
                    end else begin
                        arready_o <= 1'b1;
                    end
                end

                R_DATA: begin
                    if (rvalid_o && rready_i) begin
                        rvalid_o  <= 1'b0;
                        rresp_o   <= RESP_OKAY;
                        arready_o <= 1'b1;
                        r_state   <= R_IDLE;
                    end
                end

                default: begin
                    r_state   <= R_IDLE;
                    arready_o <= 1'b1;
                    rvalid_o  <= 1'b0;
                    rresp_o   <= RESP_OKAY;
                end
            endcase
        end
    end

endmodule
