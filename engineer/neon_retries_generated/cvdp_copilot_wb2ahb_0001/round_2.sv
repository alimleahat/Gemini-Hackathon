module wishbone_to_ahb_bridge (
    // Wishbone Ports (from WB Master)
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        cyc_i,
    input  logic        stb_i,
    input  logic [3:0]  sel_i,
    input  logic        we_i,
    input  logic [31:0] addr_i,
    input  logic [31:0] data_i,
    output logic [31:0] data_o,
    output logic        ack_o,

    // AHB Ports (to/from AHB Slave)
    input  logic        hclk,
    input  logic        hreset_n,
    input  logic [31:0] hrdata,
    input  logic [1:0]  hresp,
    input  logic        hready,
    output logic [1:0]  htrans,
    output logic [2:0]  hsize,
    output logic [2:0]  hburst,
    output logic        hwrite,
    output logic [31:0] haddr,
    output logic [31:0] hwdata
);

    // AHB transfer types
    localparam [1:0] HTRANS_IDLE   = 2'b00;
    localparam [1:0] HTRANS_BUSY   = 2'b01;
    localparam [1:0] HTRANS_NONSEQ = 2'b10;
    localparam [1:0] HTRANS_SEQ    = 2'b11;

    // AHB burst types (single transfer only)
    localparam [2:0] HBURST_SINGLE = 3'b000;

    // AHB transfer sizes
    localparam [2:0] HSIZE_BYTE     = 3'b000;
    localparam [2:0] HSIZE_HALFWORD = 3'b001;
    localparam [2:0] HSIZE_WORD     = 3'b010;

    // AHB responses
    localparam [1:0] HRESP_OKAY  = 2'b00;
    localparam [1:0] HRESP_ERROR = 2'b01;
    localparam [1:0] HRESP_RETRY = 2'b10;
    localparam [1:0] HRESP_SPLIT = 2'b11;

    // FSM states
    localparam [1:0] ST_IDLE   = 2'b00;
    localparam [1:0] ST_NONSEQ = 2'b01;
    localparam [1:0] ST_BUSY   = 2'b10;
    localparam [1:0] ST_ACK    = 2'b11;

    // Combined active-low reset
    logic rst_n;
    assign rst_n = rst_i & hreset_n;

    // Single transfer burst constant
    assign hburst = HBURST_SINGLE;

    // Internal registers
    logic [1:0]  state;
    logic [3:0]  sel_hold;
    logic [31:0] wdata_hold;

    // Combinational decode signals
    logic        sel_valid;
    logic [1:0]  addr_offset;
    logic [2:0]  size_dec;
    logic [31:0] wdata_conv;
    logic [31:0] rdata_conv;

    // Decode sel_i for validity, address fixing, hsize, and write endian conversion
    always_comb begin
        sel_valid   = 1'b1;
        addr_offset = 2'b00;
        size_dec    = HSIZE_BYTE;
        wdata_conv  = 32'h0000_0000;

        case (sel_i)
            4'b0001: begin
                addr_offset = 2'b00;
                size_dec    = HSIZE_BYTE;
                wdata_conv  = {data_i[7:0], 24'h00_0000};
            end
            4'b0010: begin
                addr_offset = 2'b01;
                size_dec    = HSIZE_BYTE;
                wdata_conv  = {8'h00, data_i[15:8], 16'h0000};
            end
            4'b0100: begin
                addr_offset = 2'b10;
                size_dec    = HSIZE_BYTE;
                wdata_conv  = {16'h0000, data_i[23:16], 8'h00};
            end
            4'b1000: begin
                addr_offset = 2'b11;
                size_dec    = HSIZE_BYTE;
                wdata_conv  = {24'h00_0000, data_i[31:24]};
            end
            4'b0011: begin
                addr_offset = 2'b00;
                size_dec    = HSIZE_HALFWORD;
                wdata_conv  = {data_i[7:0], data_i[15:8], 16'h0000};
            end
            4'b1100: begin
                addr_offset = 2'b10;
                size_dec    = HSIZE_HALFWORD;
                wdata_conv  = {16'h0000, data_i[23:16], data_i[31:24]};
            end
            4'b1111: begin
                addr_offset = 2'b00;
                size_dec    = HSIZE_WORD;
                wdata_conv  = {data_i[7:0], data_i[15:8], data_i[23:16], data_i[31:24]};
            end
            default: begin
                sel_valid   = 1'b0;
                addr_offset = 2'b00;
                size_dec    = HSIZE_BYTE;
                wdata_conv  = 32'h0000_0000;
            end
        endcase
    end

    // Read data endian conversion based on held byte enables
    always_comb begin
        case (sel_hold)
            4'b0001: rdata_conv = {24'h00_0000, hrdata[31:24]};
            4'b0010: rdata_conv = {16'h0000, hrdata[23:16], 8'h00};
            4'b0100: rdata_conv = {8'h00, hrdata[15:8], 16'h0000};
            4'b1000: rdata_conv = {hrdata[7:0], 24'h00_0000};
            4'b0011: rdata_conv = {16'h0000, hrdata[23:16], hrdata[31:24]};
            4'b1100: rdata_conv = {hrdata[7:0], hrdata[15:8], 16'h0000};
            4'b1111: rdata_conv = {hrdata[7:0], hrdata[15:8], hrdata[23:16], hrdata[31:24]};
            default: rdata_conv = 32'h0000_0000;
        endcase
    end

    // Main bridge FSM and signal holding registers
    always_ff @(posedge hclk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            htrans     <= HTRANS_IDLE;
            hsize      <= HSIZE_BYTE;
            hwrite     <= 1'b0;
            haddr      <= 32'h0000_0000;
            hwdata     <= 32'h0000_0000;
            wdata_hold <= 32'h0000_0000;
            sel_hold   <= 4'b0000;
            data_o     <= 32'h0000_0000;
            ack_o      <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    ack_o  <= 1'b0;
                    htrans <= HTRANS_IDLE;
                    if (cyc_i && stb_i) begin
                        if (sel_valid) begin
                            haddr      <= {addr_i[31:2], addr_offset};
                            hsize      <= size_dec;
                            hwrite     <= we_i;
                            sel_hold   <= sel_i;
                            wdata_hold <= wdata_conv;
                            htrans     <= HTRANS_NONSEQ;
                            state      <= ST_NONSEQ;
                        end else begin
                            // Invalid sel_i: suppress AHB transfer to avoid data corruption
                            hwrite     <= 1'b0;
                            hwdata     <= 32'h0000_0000;
                            sel_hold   <= 4'b0000;
                            wdata_hold <= 32'h0000_0000;
                            data_o     <= 32'h0000_0000;
                            ack_o      <= 1'b1;
                            state      <= ST_ACK;
                        end
                    end
                end

                ST_NONSEQ: begin
                    ack_o <= 1'b0;
                    if (hready) begin
                        // Address phase accepted; enter AHB data phase
                        htrans <= HTRANS_IDLE;
                        hwdata <= hwrite ? wdata_hold : 32'h0000_0000;
                        state  <= ST_BUSY;
                    end
                end

                ST_BUSY: begin
                    htrans <= HTRANS_IDLE;
                    if (hready) begin
                        case (hresp)
                            HRESP_OKAY: begin
                                if (!hwrite) begin
                                    data_o <= rdata_conv;
                                end
                                ack_o <= 1'b1;
                                state <= ST_ACK;
                            end
                            HRESP_RETRY, HRESP_SPLIT: begin
                                // Re-issue address phase with held attributes
                                htrans <= HTRANS_NONSEQ;
                                ack_o  <= 1'b0;
                                state  <= ST_NONSEQ;
                            end
                            default: begin
                                // HRESP_ERROR: terminate WB cycle cleanly
                                data_o <= 32'h0000_0000;
                                ack_o  <= 1'b1;
                                state  <= ST_ACK;
                            end
                        endcase
                    end
                end

                ST_ACK: begin
                    ack_o  <= 1'b0;
                    htrans <= HTRANS_IDLE;
                    state  <= ST_IDLE;
                end

                default: begin
                    ack_o  <= 1'b0;
                    htrans <= HTRANS_IDLE;
                    state  <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
