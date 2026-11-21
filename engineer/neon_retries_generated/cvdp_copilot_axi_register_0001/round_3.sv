module axi_register #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  logic                        clk_i,
    input  logic                        rst_n_i,

    // AXI4-Lite Write Address Channel
    input  logic [ADDR_WIDTH-1:0]       awaddr_i,
    input  logic                        awvalid_i,
    output logic                        awready_o,

    // AXI4-Lite Write Data Channel
    input  logic [DATA_WIDTH-1:0]       wdata_i,
    input  logic                        wvalid_i,
    input  logic [(DATA_WIDTH/8)-1:0]   wstrb_i,
    output logic                        wready_o,

    // AXI4-Lite Write Response Channel
    output logic [1:0]                  bresp_o,
    output logic                        bvalid_o,
    input  logic                        bready_i,

    // AXI4-Lite Read Address Channel
    input  logic [ADDR_WIDTH-1:0]       araddr_i,
    input  logic                        arvalid_i,
    output logic                        arready_o,

    // AXI4-Lite Read Data Channel
    output logic [DATA_WIDTH-1:0]       rdata_o,
    output logic                        rvalid_o,
    output logic [1:0]                  rresp_o,
    input  logic                        rready_i,

    // Hardware Control and Status Interface
    input  logic                        done_i,
    output logic [19:0]                 beat_o,
    output logic                        start_o,
    output logic                        writeback_o
);

    // Register address offsets (lower 12 bits)
    localparam [11:0] ADDR_BEAT      = 12'h100;
    localparam [11:0] ADDR_START     = 12'h200;
    localparam [11:0] ADDR_DONE      = 12'h300;
    localparam [11:0] ADDR_WRITEBACK = 12'h400;
    localparam [11:0] ADDR_ID        = 12'h500;

    // Fixed identification register value
    localparam [31:0] ID_VALUE       = 32'h0001_0001;

    // AXI4-Lite response encodings
    localparam [1:0]  RESP_OKAY      = 2'b00;
    localparam [1:0]  RESP_SLVERR    = 2'b10;

    // Write FSM states
    localparam [1:0]  W_RST          = 2'd0;
    localparam [1:0]  W_IDLE         = 2'd1;
    localparam [1:0]  W_DATA         = 2'd2;
    localparam [1:0]  W_RESP         = 2'd3;

    // Read FSM states
    localparam [1:0]  R_RST          = 2'd0;
    localparam [1:0]  R_IDLE         = 2'd1;
    localparam [1:0]  R_DATA         = 2'd2;

    // FSM state registers
    logic [1:0] w_state;
    logic [1:0] r_state;

    // Latched write address (lower 12 bits)
    logic [11:0] awaddr_r;

    // Internal hardware registers
    logic [19:0] beat_r;
    logic        start_r;
    logic        writeback_r;
    logic        done_r;
    logic        done_i_d;

    // Helper signals for write operations and done detection
    logic write_fire;
    logic full_write;
    logic done_rise;
    logic clear_done;

    assign write_fire = (w_state == W_DATA) && wvalid_i && wready_o;
    assign full_write = &wstrb_i;
    assign done_rise  = done_i && !done_i_d;
    assign clear_done = write_fire && full_write && (awaddr_r == ADDR_DONE) && wdata_i[0];

    // Width-safe conversions for register data
    logic [19:0]           wdata_beat;
    logic [DATA_WIDTH-1:0] beat_rdata;
    logic [DATA_WIDTH-1:0] start_rdata;
    logic [DATA_WIDTH-1:0] done_rdata;
    logic [DATA_WIDTH-1:0] writeback_rdata;
    logic [DATA_WIDTH-1:0] id_rdata;

    generate
        if (DATA_WIDTH >= 20) begin : g_beat_w_ge20
            assign wdata_beat = wdata_i[19:0];
        end else begin : g_beat_w_lt20
            assign wdata_beat = {{(20 - DATA_WIDTH){1'b0}}, wdata_i};
        end

        if (DATA_WIDTH > 20) begin : g_beat_r_gt20
            assign beat_rdata = {{(DATA_WIDTH - 20){1'b0}}, beat_r};
        end else if (DATA_WIDTH == 20) begin : g_beat_r_eq20
            assign beat_rdata = beat_r;
        end else begin : g_beat_r_lt20
            assign beat_rdata = beat_r[DATA_WIDTH-1:0];
        end

        if (DATA_WIDTH > 32) begin : g_id_r_gt32
            assign id_rdata = {{(DATA_WIDTH - 32){1'b0}}, ID_VALUE};
        end else if (DATA_WIDTH == 32) begin : g_id_r_eq32
            assign id_rdata = ID_VALUE;
        end else begin : g_id_r_lt32
            assign id_rdata = ID_VALUE[DATA_WIDTH-1:0];
        end
    endgenerate

    assign start_rdata     = {{(DATA_WIDTH - 1){1'b0}}, start_r};
    assign done_rdata      = {{(DATA_WIDTH - 1){1'b0}}, (done_r | done_rise)};
    assign writeback_rdata = {{(DATA_WIDTH - 1){1'b0}}, writeback_r};

    // Output assignments
    assign beat_o      = beat_r;
    assign start_o     = start_r;
    assign writeback_o = writeback_r;

    // Done status tracking (latched on done_i rising edge, cleared on W1C to Done register)
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            done_i_d <= 1'b0;
            done_r   <= 1'b0;
        end else begin
            done_i_d <= done_i;
            if (done_rise) begin
                done_r <= 1'b1;
            end else if (clear_done) begin
                done_r <= 1'b0;
            end
        end
    end

    // Write transaction FSM and register updates
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            w_state     <= W_RST;
            awready_o   <= 1'b0;
            wready_o    <= 1'b0;
            bvalid_o    <= 1'b0;
            bresp_o     <= RESP_OKAY;
            awaddr_r    <= 12'h000;
            beat_r      <= 20'd0;
            start_r     <= 1'b0;
            writeback_r <= 1'b0;
        end else begin
            case (w_state)
                W_RST: begin
                    awready_o <= 1'b1;
                    wready_o  <= 1'b0;
                    bvalid_o  <= 1'b0;
                    w_state   <= W_IDLE;
                end

                W_IDLE: begin
                    if (awvalid_i && awready_o) begin
                        awaddr_r  <= awaddr_i[11:0];
                        awready_o <= 1'b0;
                        wready_o  <= 1'b1;
                        w_state   <= W_DATA;
                    end
                end

                W_DATA: begin
                    if (wvalid_i && wready_o) begin
                        wready_o <= 1'b0;
                        bvalid_o <= 1'b1;
                        w_state  <= W_RESP;

                        case (awaddr_r)
                            ADDR_BEAT: begin
                                bresp_o <= RESP_OKAY;
                                if (full_write) begin
                                    beat_r <= wdata_beat;
                                end
                            end

                            ADDR_START: begin
                                bresp_o <= RESP_OKAY;
                                if (full_write) begin
                                    start_r <= wdata_i[0];
                                end
                            end

                            ADDR_DONE: begin
                                bresp_o <= RESP_OKAY;
                            end

                            ADDR_WRITEBACK: begin
                                bresp_o <= RESP_OKAY;
                                if (full_write) begin
                                    writeback_r <= wdata_i[0];
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
                        awready_o <= 1'b1;
                        w_state   <= W_IDLE;
                    end
                end

                default: begin
                    w_state   <= W_RST;
                    awready_o <= 1'b0;
                    wready_o  <= 1'b0;
                    bvalid_o  <= 1'b0;
                end
            endcase
        end
    end

    // Read transaction FSM
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            r_state   <= R_RST;
            arready_o <= 1'b0;
            rvalid_o  <= 1'b0;
            rdata_o   <= {DATA_WIDTH{1'b0}};
            rresp_o   <= RESP_OKAY;
        end else begin
            case (r_state)
                R_RST: begin
                    arready_o <= 1'b1;
                    rvalid_o  <= 1'b0;
                    r_state   <= R_IDLE;
                end

                R_IDLE: begin
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
                                rdata_o <= writeback_rdata;
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
                        r_state   <= R_IDLE;
                    end
                end

                default: begin
                    r_state   <= R_RST;
                    arready_o <= 1'b0;
                    rvalid_o  <= 1'b0;
                end
            endcase
        end
    end

endmodule
