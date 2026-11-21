module axi_register #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input  logic                      clk_i,
    input  logic                      rst_n_i,
    input  logic [ADDR_WIDTH-1:0]     awaddr_i,
    input  logic                      awvalid_i,
    output logic                      awready_o,
    input  logic [DATA_WIDTH-1:0]     wdata_i,
    input  logic                      wvalid_i,
    input  logic [(DATA_WIDTH/8)-1:0] wstrb_i,
    output logic                      wready_o,
    output logic [1:0]                bresp_o,
    output logic                      bvalid_o,
    input  logic                      bready_i,
    input  logic [ADDR_WIDTH-1:0]     araddr_i,
    input  logic                      arvalid_i,
    output logic                      arready_o,
    output logic [DATA_WIDTH-1:0]     rdata_o,
    output logic                      rvalid_o,
    output logic [1:0]                rresp_o,
    input  logic                      rready_i,
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

    localparam logic [1:0]  RESP_OKAY      = 2'b00;
    localparam logic [1:0]  RESP_SLVERR    = 2'b10;

    localparam logic [31:0] ID_VALUE       = 32'h0001_0001;

    typedef enum logic [1:0] {
        W_ADDR = 2'b00,
        W_DATA = 2'b01,
        W_RESP = 2'b10
    } w_state_t;

    typedef enum logic [0:0] {
        R_ADDR = 1'b0,
        R_DATA = 1'b1
    } r_state_t;

    w_state_t        w_state;
    r_state_t        r_state;

    logic [11:0]     awaddr_reg;

    logic [19:0]     beat_reg;
    logic            start_reg;
    logic            done_reg;
    logic            done_i_d;
    logic            writeback_reg;

    logic [19:0]           wdata_beat;
    logic [DATA_WIDTH-1:0] rdata_beat;
    logic [DATA_WIDTH-1:0] rdata_id;
    logic                  done_status;

    generate
        if (DATA_WIDTH >= 20) begin : gen_wdata_beat_ge20
            assign wdata_beat = wdata_i[19:0];
        end else begin : gen_wdata_beat_lt20
            assign wdata_beat = {{(20 - DATA_WIDTH){1'b0}}, wdata_i};
        end

        if (DATA_WIDTH > 20) begin : gen_rdata_beat_gt20
            assign rdata_beat = {{(DATA_WIDTH - 20){1'b0}}, beat_reg};
        end else if (DATA_WIDTH == 20) begin : gen_rdata_beat_eq20
            assign rdata_beat = beat_reg;
        end else begin : gen_rdata_beat_lt20
            assign rdata_beat = beat_reg[DATA_WIDTH-1:0];
        end

        if (DATA_WIDTH > 32) begin : gen_rdata_id_gt32
            assign rdata_id = {{(DATA_WIDTH - 32){1'b0}}, ID_VALUE};
        end else if (DATA_WIDTH == 32) begin : gen_rdata_id_eq32
            assign rdata_id = ID_VALUE;
        end else begin : gen_rdata_id_lt32
            assign rdata_id = ID_VALUE[DATA_WIDTH-1:0];
        end
    endgenerate

    assign done_status = done_reg | (done_i & ~done_i_d);

    assign beat_o      = beat_reg;
    assign start_o     = start_reg;
    assign writeback_o = writeback_reg;

    // Write channel FSM and register updates
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            w_state       <= W_ADDR;
            awready_o     <= 1'b0;
            wready_o      <= 1'b0;
            bvalid_o      <= 1'b0;
            bresp_o       <= RESP_OKAY;
            awaddr_reg    <= 12'h000;
            beat_reg      <= 20'd0;
            start_reg     <= 1'b0;
            done_reg      <= 1'b0;
            done_i_d      <= 1'b0;
            writeback_reg <= 1'b0;
        end else begin
            done_i_d <= done_i;
            if (done_i && !done_i_d) begin
                done_reg <= 1'b1;
            end

            case (w_state)
                W_ADDR: begin
                    if (awvalid_i && awready_o) begin
                        awaddr_reg <= awaddr_i[11:0];
                        awready_o  <= 1'b0;
                        wready_o   <= 1'b1;
                        w_state    <= W_DATA;
                    end else begin
                        awready_o  <= 1'b1;
                        wready_o   <= 1'b0;
                    end
                end

                W_DATA: begin
                    if (wvalid_i && wready_o) begin
                        wready_o <= 1'b0;
                        bvalid_o <= 1'b1;
                        w_state  <= W_RESP;

                        case (awaddr_reg)
                            ADDR_BEAT: begin
                                if (&wstrb_i) begin
                                    beat_reg <= wdata_beat;
                                end
                                bresp_o <= RESP_OKAY;
                            end

                            ADDR_START: begin
                                if (&wstrb_i) begin
                                    start_reg <= wdata_i[0];
                                end
                                bresp_o <= RESP_OKAY;
                            end

                            ADDR_DONE: begin
                                if (&wstrb_i) begin
                                    if (wdata_i[0]) begin
                                        done_reg <= 1'b0;
                                    end
                                end
                                bresp_o <= RESP_OKAY;
                            end

                            ADDR_WRITEBACK: begin
                                if (&wstrb_i) begin
                                    writeback_reg <= wdata_i[0];
                                end
                                bresp_o <= RESP_OKAY;
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
                        w_state   <= W_ADDR;
                    end
                end

                default: begin
                    w_state   <= W_ADDR;
                    awready_o <= 1'b0;
                    wready_o  <= 1'b0;
                    bvalid_o  <= 1'b0;
                    bresp_o   <= RESP_OKAY;
                end
            endcase
        end
    end

    // Read channel FSM
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            r_state   <= R_ADDR;
            arready_o <= 1'b0;
            rvalid_o  <= 1'b0;
            rdata_o   <= {DATA_WIDTH{1'b0}};
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
                                rdata_o <= rdata_beat;
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_START: begin
                                rdata_o <= {{(DATA_WIDTH - 1){1'b0}}, start_reg};
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_DONE: begin
                                rdata_o <= {{(DATA_WIDTH - 1){1'b0}}, done_status};
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_WRITEBACK: begin
                                rdata_o <= {{(DATA_WIDTH - 1){1'b0}}, writeback_reg};
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_ID: begin
                                rdata_o <= rdata_id;
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
                        r_state   <= R_ADDR;
                    end
                end

                default: begin
                    r_state   <= R_ADDR;
                    arready_o <= 1'b0;
                    rvalid_o  <= 1'b0;
                    rdata_o   <= {DATA_WIDTH{1'b0}};
                    rresp_o   <= RESP_OKAY;
                end
            endcase
        end
    end

endmodule
