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

    localparam int RDATA_REG_W = (DATA_WIDTH < 20) ? DATA_WIDTH : 20;

    // Decoded write address registers (replaces 12-bit awaddr_reg)
    logic                  w_addr_ok;
    logic [1:0]            w_sel;

    // Hardware control/status registers
    logic [19:0]           beat_reg;
    logic                  start_reg;
    logic                  done_reg;
    logic                  done_i_d;
    logic                  writeback_reg;

    // Read channel data and error registers
    logic [RDATA_REG_W-1:0] rdata_reg;
    logic                   rresp_err;

    // Write channel combinational signals
    logic                  aw_fire;
    logic                  aw_lo_zero;
    logic                  aw_hi_ok;
    logic                  w_addr_ok_d;
    logic                  w_full_fire;
    logic                  beat_en;
    logic                  start_en;
    logic                  wb_en;
    logic [19:0]           wdata_beat;
    logic                  done_status;

    // Read channel combinational signals
    logic                   ar_fire;
    logic                   ar_lo_zero;
    logic                   ar_base_ok;
    logic                   is_ar_beat;
    logic                   ar_addr_err;
    logic                   rdata0_lo;
    logic                   rdata0_next;
    logic [RDATA_REG_W-1:0] rdata_next;

    generate
        if (DATA_WIDTH >= 20) begin : gen_wdata_beat_ge20
            assign wdata_beat = wdata_i[19:0];
        end else begin : gen_wdata_beat_lt20
            assign wdata_beat = {{(20 - DATA_WIDTH){1'b0}}, wdata_i};
        end

        if (DATA_WIDTH > 20) begin : gen_rdata_o_gt20
            assign rdata_o = {{(DATA_WIDTH - 20){1'b0}}, rdata_reg};
        end else begin : gen_rdata_o_le20
            assign rdata_o = rdata_reg;
        end
    endgenerate

    assign done_status = done_reg | (done_i & ~done_i_d);

    assign beat_o      = beat_reg;
    assign start_o     = start_reg;
    assign writeback_o = writeback_reg;
    assign bresp_o     = {bvalid_o & ~w_addr_ok, 1'b0};
    assign rresp_o     = {rresp_err, 1'b0};

    // Write channel address decode and write enables
    // Valid write offsets: 0x100 (sel=01), 0x200 (sel=10), 0x300 (sel=11), 0x400 (sel=00)
    assign aw_fire     = awready_o & awvalid_i;
    assign aw_lo_zero  = (awaddr_i[5:0] == 6'b0);
    assign aw_hi_ok    = (awaddr_i[7:6] == 2'b00) & ~awaddr_i[11] &
                         (awaddr_i[10] ^ (awaddr_i[9] | awaddr_i[8]));
    assign w_addr_ok_d = aw_lo_zero & aw_hi_ok;

    assign w_full_fire = wready_o & wvalid_i & (&wstrb_i);
    assign beat_en     = w_full_fire & w_addr_ok & (w_sel == 2'b01);
    assign start_en    = w_full_fire & w_addr_ok & (w_sel == 2'b10);
    assign wb_en       = w_full_fire & w_addr_ok & (w_sel == 2'b00);

    // Write channel FSM and register updates
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            awready_o     <= 1'b0;
            wready_o      <= 1'b0;
            bvalid_o      <= 1'b0;
            w_addr_ok     <= 1'b0;
            w_sel         <= 2'b00;
            beat_reg      <= 20'd0;
            start_reg     <= 1'b0;
            done_reg      <= 1'b0;
            done_i_d      <= 1'b0;
            writeback_reg <= 1'b0;
        end else begin
            awready_o <= (~wready_o & ~bvalid_o & ~aw_fire) | (bvalid_o & bready_i);
            wready_o  <= aw_fire | (wready_o & ~wvalid_i);
            bvalid_o  <= (wready_o & wvalid_i) | (bvalid_o & ~bready_i);

            if (aw_fire) begin
                w_addr_ok <= w_addr_ok_d;
                w_sel     <= awaddr_i[9:8];
            end

            if (beat_en) begin
                beat_reg <= wdata_beat;
            end

            if (start_en) begin
                start_reg <= wdata_i[0];
            end

            if (wb_en) begin
                writeback_reg <= wdata_i[0];
            end

            done_i_d <= done_i;
            done_reg <= done_status & ~(w_full_fire & w_addr_ok & w_sel[1] & w_sel[0] & wdata_i[0]);
        end
    end

    // Read channel address decode and read data mux
    // Valid read offsets: 0x100, 0x200, 0x300, 0x400, 0x500 (ID = 32'h0001_0001)
    assign ar_fire     = arready_o & arvalid_i;
    assign ar_lo_zero  = (araddr_i[5:0] == 6'b0);
    assign ar_base_ok  = ar_lo_zero & ~araddr_i[6] & ~araddr_i[7] & ~araddr_i[11];
    assign is_ar_beat  = ar_base_ok & (araddr_i[10:8] == 3'b001);
    assign ar_addr_err = ~(ar_base_ok & (|araddr_i[10:8]) & ~(araddr_i[10] & araddr_i[9]));

    always_comb begin
        case (araddr_i[9:8])
            2'b01:   rdata0_lo = beat_reg[0];
            2'b10:   rdata0_lo = start_reg;
            2'b11:   rdata0_lo = done_status;
            default: rdata0_lo = 1'b0;
        endcase
    end

    always_comb begin
        if (!ar_base_ok) begin
            rdata0_next = 1'b0;
        end else if (!araddr_i[10]) begin
            rdata0_next = rdata0_lo;
        end else if (araddr_i[9]) begin
            rdata0_next = 1'b0;
        end else if (araddr_i[8]) begin
            rdata0_next = 1'b1;
        end else begin
            rdata0_next = writeback_reg;
        end
    end

    always_comb begin
        rdata_next    = {RDATA_REG_W{1'b0}};
        rdata_next[0] = rdata0_next;
        for (int i = 1; i < RDATA_REG_W; i++) begin
            if (i == 16) begin
                rdata_next[i] = (ar_base_ok && (araddr_i[9:8] == 2'b01))
                                ? (araddr_i[10] ? 1'b1 : beat_reg[16])
                                : 1'b0;
            end else begin
                rdata_next[i] = is_ar_beat ? beat_reg[i] : 1'b0;
            end
        end
    end

    // Read channel FSM
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            arready_o <= 1'b0;
            rvalid_o  <= 1'b0;
            rdata_reg <= {RDATA_REG_W{1'b0}};
            rresp_err <= 1'b0;
        end else begin
            arready_o <= (~rvalid_o & ~ar_fire) | (rvalid_o & rready_i);
            rvalid_o  <= ar_fire | (rvalid_o & ~rready_i);
            rresp_err <= ar_fire ? ar_addr_err : (rresp_err & ~rready_i);

            if (ar_fire) begin
                rdata_reg <= rdata_next;
            end
        end
    end

endmodule
