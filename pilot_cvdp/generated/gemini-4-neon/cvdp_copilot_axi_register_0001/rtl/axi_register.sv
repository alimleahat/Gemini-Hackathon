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
    input  logic                      wvalid_i,
    input  logic [(DATA_WIDTH/8)-1:0] wstrb_i,
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
    output logic                      rvalid_o,
    output logic [1:0]                rresp_o,
    input  logic                      rready_i,

    // Hardware Control & Status Interface
    input  logic                      done_i,
    output logic [19:0]               beat_o,
    output logic                      start_o,
    output logic                      writeback_o
);

    // Register address offsets (lower 12 bits)
    localparam logic [11:0] ADDR_BEAT      = 12'h100;
    localparam logic [11:0] ADDR_START     = 12'h200;
    localparam logic [11:0] ADDR_DONE      = 12'h300;
    localparam logic [11:0] ADDR_WRITEBACK = 12'h400;
    localparam logic [11:0] ADDR_ID        = 12'h500;

    // Fixed Identification Register value
    localparam logic [31:0] ID_VALUE       = 32'h0001_0001;

    // AXI4-Lite response codes
    localparam logic [1:0]  RESP_OKAY      = 2'b00;
    localparam logic [1:0]  RESP_SLVERR    = 2'b10;

    // Write FSM states
    localparam logic [1:0]  W_IDLE         = 2'b00;
    localparam logic [1:0]  W_DATA         = 2'b01;
    localparam logic [1:0]  W_RESP         = 2'b10;

    // Read FSM states
    localparam logic        R_IDLE         = 1'b0;
    localparam logic        R_DATA         = 1'b1;

    // FSM state registers
    logic [1:0]  wstate;
    logic        rstate;

    // Latched write address offset
    logic [11:0] awaddr_reg;

    // Hardware registers
    logic [19:0] beat_reg;
    logic        start_reg;
    logic        done_reg;
    logic        done_i_d;
    logic        writeback_reg;

    // Internal control signals
    logic        w_handshake;
    logic        full_write;
    logic        done_rise;
    logic        done_clr;

    // Parameterized width-safe data conversion wires
    logic [19:0]           beat_wdata;
    logic [DATA_WIDTH-1:0] beat_rdata;
    logic [DATA_WIDTH-1:0] id_rdata;

    generate
        if (DATA_WIDTH >= 20) begin : gen_beat_wide
            assign beat_wdata = wdata_i[19:0];
            if (DATA_WIDTH > 20) begin : gen_beat_pad
                assign beat_rdata = {{(DATA_WIDTH-20){1'b0}}, beat_reg};
            end else begin : gen_beat_exact
                assign beat_rdata = beat_reg;
            end
        end else begin : gen_beat_narrow
            assign beat_wdata = {{(20-DATA_WIDTH){1'b0}}, wdata_i};
            assign beat_rdata = beat_reg[DATA_WIDTH-1:0];
        end

        if (DATA_WIDTH > 32) begin : gen_id_wide
            assign id_rdata = {{(DATA_WIDTH-32){1'b0}}, ID_VALUE};
        end else if (DATA_WIDTH == 32) begin : gen_id_exact
            assign id_rdata = ID_VALUE;
        end else begin : gen_id_narrow
            assign id_rdata = ID_VALUE[DATA_WIDTH-1:0];
        end
    endgenerate

    assign w_handshake = (wstate == W_DATA) && wvalid_i && wready_o;
    assign full_write  = &wstrb_i;
    assign done_rise   = done_i && !done_i_d;
    assign done_clr    = w_handshake && full_write && (awaddr_reg == ADDR_DONE) && wdata_i[0];

    // Hardware outputs
    assign beat_o      = beat_reg;
    assign start_o     = start_reg;
    assign writeback_o = writeback_reg;

    // Done status register (latched on done_i rising edge, cleared by writing 1)
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            done_reg <= 1'b0;
            done_i_d <= 1'b0;
        end else begin
            done_i_d <= done_i;
            if (done_rise) begin
                done_reg <= 1'b1;
            end else if (done_clr) begin
                done_reg <= 1'b0;
            end
        end
    end

    // Write transaction FSM and register updates
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wstate        <= W_IDLE;
            awready_o     <= 1'b0;
            wready_o      <= 1'b0;
            bvalid_o      <= 1'b0;
            bresp_o       <= RESP_OKAY;
            awaddr_reg    <= 12'h000;
            beat_reg      <= 20'd0;
            start_reg     <= 1'b0;
            writeback_reg <= 1'b0;
        end else begin
            case (wstate)
                W_IDLE: begin
                    bvalid_o <= 1'b0;
                    wready_o <= 1'b0;
                    if (!awready_o) begin
                        awready_o <= 1'b1;
                    end else if (awvalid_i) begin
                        awready_o  <= 1'b0;
                        awaddr_reg <= awaddr_i[11:0];
                        wready_o   <= 1'b1;
                        wstate     <= W_DATA;
                    end
                end

                W_DATA: begin
                    if (wvalid_i && wready_o) begin
                        wready_o <= 1'b0;
                        bvalid_o <= 1'b1;
                        wstate   <= W_RESP;

                        case (awaddr_reg)
                            ADDR_BEAT: begin
                                if (full_write) begin
                                    beat_reg <= beat_wdata;
                                end
                                bresp_o <= RESP_OKAY;
                            end

                            ADDR_START: begin
                                if (full_write) begin
                                    start_reg <= wdata_i[0];
                                end
                                bresp_o <= RESP_OKAY;
                            end

                            ADDR_DONE: begin
                                bresp_o <= RESP_OKAY;
                            end

                            ADDR_WRITEBACK: begin
                                if (full_write) begin
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
                        awready_o <= 1'b1;
                        wstate    <= W_IDLE;
                    end
                end

                default: begin
                    wstate    <= W_IDLE;
                    awready_o <= 1'b0;
                    wready_o  <= 1'b0;
                    bvalid_o  <= 1'b0;
                    bresp_o   <= RESP_OKAY;
                end
            endcase
        end
    end

    // Read transaction FSM
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rstate    <= R_IDLE;
            arready_o <= 1'b0;
            rvalid_o  <= 1'b0;
            rdata_o   <= {DATA_WIDTH{1'b0}};
            rresp_o   <= RESP_OKAY;
        end else begin
            case (rstate)
                R_IDLE: begin
                    rvalid_o <= 1'b0;
                    if (!arready_o) begin
                        arready_o <= 1'b1;
                    end else if (arvalid_i) begin
                        arready_o <= 1'b0;
                        rvalid_o  <= 1'b1;
                        rstate    <= R_DATA;

                        case (araddr_i[11:0])
                            ADDR_BEAT: begin
                                rdata_o <= beat_rdata;
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_START: begin
                                rdata_o <= {{(DATA_WIDTH-1){1'b0}}, start_reg};
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_DONE: begin
                                rdata_o <= {{(DATA_WIDTH-1){1'b0}}, (done_reg | done_rise)};
                                rresp_o <= RESP_OKAY;
                            end

                            ADDR_WRITEBACK: begin
                                rdata_o <= {{(DATA_WIDTH-1){1'b0}}, writeback_reg};
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
                    end
                end

                R_DATA: begin
                    if (rvalid_o && rready_i) begin
                        rvalid_o  <= 1'b0;
                        arready_o <= 1'b1;
                        rstate    <= R_IDLE;
                    end
                end

                default: begin
                    rstate    <= R_IDLE;
                    arready_o <= 1'b0;
                    rvalid_o  <= 1'b0;
                    rdata_o   <= {DATA_WIDTH{1'b0}};
                    rresp_o   <= RESP_OKAY;
                end
            endcase
        end
    end

endmodule
