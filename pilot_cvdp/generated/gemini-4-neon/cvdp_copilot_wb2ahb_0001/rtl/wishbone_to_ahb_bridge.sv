module wishbone_to_ahb_bridge (
    // Wishbone Master Interface
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

    // AHB Slave Interface
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

    // AHB Transfer Type Encodings
    localparam logic [1:0] HTRANS_IDLE   = 2'b00;
    localparam logic [1:0] HTRANS_BUSY   = 2'b01;
    localparam logic [1:0] HTRANS_NONSEQ = 2'b10;

    // AHB Burst Type Encoding (Single transfer only)
    localparam logic [2:0] HBURST_SINGLE = 3'b000;

    // AHB Transfer Size Encodings
    localparam logic [2:0] HSIZE_BYTE     = 3'b000;
    localparam logic [2:0] HSIZE_HALFWORD = 3'b001;
    localparam logic [2:0] HSIZE_WORD     = 3'b010;

    // AHB Response Encodings
    localparam logic [1:0] HRESP_RETRY = 2'b10;
    localparam logic [1:0] HRESP_SPLIT = 2'b11;

    // FSM States
    localparam logic [1:0] ST_IDLE     = 2'b00;
    localparam logic [1:0] ST_BUSY     = 2'b01;
    localparam logic [1:0] ST_NONSEQ   = 2'b10;
    localparam logic [1:0] ST_WAIT_ACK = 2'b11;

    // Combined active-low reset (asserted if either rst_i or hreset_n is low)
    logic rst_n;
    assign rst_n = rst_i & hreset_n;

    // Single burst transfers only
    assign hburst = HBURST_SINGLE;

    // Combinational decode signals from Wishbone inputs
    logic        sel_valid;
    logic [1:0]  addr_fix;
    logic [2:0]  hsize_dec;
    logic [31:0] wdata_endian;
    logic [31:0] rdata_endian;

    // Internal holding and handshake registers
    logic [1:0]  state;
    logic [3:0]  sel_reg;
    logic        we_reg;
    logic [31:0] wdata_reg;
    logic [31:0] rdata_latched;
    logic        ahb_done;
    logic        wb_ack_done;

    // Decode sel_i for address fixing, transfer size, validity, and write endian conversion
    always_comb begin
        sel_valid    = 1'b1;
        addr_fix     = 2'b00;
        hsize_dec    = HSIZE_BYTE;
        wdata_endian = 32'h0000_0000;

        case (sel_i)
            4'b0001: begin
                addr_fix     = 2'b00;
                hsize_dec    = HSIZE_BYTE;
                wdata_endian = {data_i[7:0], 24'h000000};
            end
            4'b0010: begin
                addr_fix     = 2'b01;
                hsize_dec    = HSIZE_BYTE;
                wdata_endian = {8'h00, data_i[15:8], 16'h0000};
            end
            4'b0100: begin
                addr_fix     = 2'b10;
                hsize_dec    = HSIZE_BYTE;
                wdata_endian = {16'h0000, data_i[23:16], 8'h00};
            end
            4'b1000: begin
                addr_fix     = 2'b11;
                hsize_dec    = HSIZE_BYTE;
                wdata_endian = {24'h000000, data_i[31:24]};
            end
            4'b0011: begin
                addr_fix     = 2'b00;
                hsize_dec    = HSIZE_HALFWORD;
                wdata_endian = {data_i[7:0], data_i[15:8], 16'h0000};
            end
            4'b1100: begin
                addr_fix     = 2'b10;
                hsize_dec    = HSIZE_HALFWORD;
                wdata_endian = {16'h0000, data_i[23:16], data_i[31:24]};
            end
            4'b1111: begin
                addr_fix     = 2'b00;
                hsize_dec    = HSIZE_WORD;
                wdata_endian = {data_i[7:0], data_i[15:8], data_i[23:16], data_i[31:24]};
            end
            default: begin
                sel_valid    = 1'b0;
                addr_fix     = 2'b00;
                hsize_dec    = HSIZE_BYTE;
                wdata_endian = 32'h0000_0000;
            end
        endcase
    end

    // Read data endian conversion based on held byte-enable selection
    always_comb begin
        case (sel_reg)
            4'b0001: rdata_endian = {24'h000000, hrdata[31:24]};
            4'b0010: rdata_endian = {16'h0000, hrdata[23:16], 8'h00};
            4'b0100: rdata_endian = {8'h00, hrdata[15:8], 16'h0000};
            4'b1000: rdata_endian = {hrdata[7:0], 24'h000000};
            4'b0011: rdata_endian = {16'h0000, hrdata[23:16], hrdata[31:24]};
            4'b1100: rdata_endian = {hrdata[7:0], hrdata[15:8], 16'h0000};
            4'b1111: rdata_endian = {hrdata[7:0], hrdata[15:8], hrdata[23:16], hrdata[31:24]};
            default: rdata_endian = 32'h0000_0000;
        endcase
    end

    // AHB-side FSM and transaction holding registers
    always_ff @(posedge hclk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            htrans        <= HTRANS_IDLE;
            haddr         <= 32'h0000_0000;
            hsize         <= HSIZE_BYTE;
            hwrite        <= 1'b0;
            hwdata        <= 32'h0000_0000;
            sel_reg       <= 4'b0000;
            we_reg        <= 1'b0;
            wdata_reg     <= 32'h0000_0000;
            rdata_latched <= 32'h0000_0000;
            ahb_done      <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    htrans   <= HTRANS_IDLE;
                    ahb_done <= 1'b0;

                    if (cyc_i && stb_i && !wb_ack_done) begin
                        if (sel_valid) begin
                            haddr     <= {addr_i[31:2], addr_fix};
                            hsize     <= hsize_dec;
                            hwrite    <= we_i;
                            htrans    <= HTRANS_NONSEQ;
                            sel_reg   <= sel_i;
                            we_reg    <= we_i;
                            wdata_reg <= wdata_endian;
                            state     <= ST_NONSEQ;
                        end else begin
                            // Gracefully complete invalid sel_i without issuing AHB transfer
                            htrans        <= HTRANS_IDLE;
                            hwrite        <= 1'b0;
                            hwdata        <= 32'h0000_0000;
                            rdata_latched <= 32'h0000_0000;
                            ahb_done      <= 1'b1;
                            state         <= ST_WAIT_ACK;
                        end
                    end
                end

                ST_NONSEQ: begin
                    // Hold address phase signals until AHB slave asserts hready
                    if (hready) begin
                        htrans <= HTRANS_IDLE;
                        hwdata <= we_reg ? wdata_reg : 32'h0000_0000;
                        state  <= ST_BUSY;
                    end
                end

                ST_BUSY: begin
                    // Data phase: hold hwdata and wait for AHB slave hready
                    htrans <= HTRANS_IDLE;
                    if (hready) begin
                        if ((hresp == HRESP_RETRY) || (hresp == HRESP_SPLIT)) begin
                            htrans <= HTRANS_NONSEQ;
                            state  <= ST_NONSEQ;
                        end else begin
                            rdata_latched <= we_reg ? 32'h0000_0000 : rdata_endian;
                            ahb_done      <= 1'b1;
                            state         <= ST_WAIT_ACK;
                        end
                    end
                end

                ST_WAIT_ACK: begin
                    htrans <= HTRANS_IDLE;
                    if (wb_ack_done) begin
                        ahb_done <= 1'b0;
                        state    <= ST_IDLE;
                    end
                end

                default: begin
                    htrans   <= HTRANS_IDLE;
                    ahb_done <= 1'b0;
                    state    <= ST_IDLE;
                end
            endcase
        end
    end

    // Wishbone-side acknowledge and read data output logic
    always_ff @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            ack_o       <= 1'b0;
            data_o      <= 32'h0000_0000;
            wb_ack_done <= 1'b0;
        end else begin
            if (ahb_done && !wb_ack_done) begin
                ack_o       <= 1'b1;
                data_o      <= rdata_latched;
                wb_ack_done <= 1'b1;
            end else begin
                ack_o <= 1'b0;
                if (!ahb_done) begin
                    wb_ack_done <= 1'b0;
                end
            end
        end
    end

endmodule
