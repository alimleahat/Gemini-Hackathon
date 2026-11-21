module wishbone_to_ahb_bridge (
    // Wishbone Ports
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

    // AHB Ports
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

    localparam logic [1:0] HTRANS_IDLE   = 2'b00;
    localparam logic [1:0] HTRANS_BUSY   = 2'b01;
    localparam logic [1:0] HTRANS_NONSEQ = 2'b10;

    localparam logic [1:0] ST_IDLE   = 2'd0;
    localparam logic [1:0] ST_NONSEQ = 2'd1;
    localparam logic [1:0] ST_DATA   = 2'd2;
    localparam logic [1:0] ST_ACK    = 2'd3;

    logic [1:0]  state;
    logic [3:0]  sel_r;
    logic        sel_valid;
    logic [31:0] next_haddr;
    logic [2:0]  next_hsize;
    logic [31:0] next_hwdata;
    logic [31:0] converted_rdata;

    logic rst_n;
    assign rst_n  = rst_i & hreset_n;
    assign hburst = 3'b000;

    always_comb begin
        sel_valid   = 1'b1;
        next_haddr  = {addr_i[31:2], 2'b00};
        next_hsize  = 3'b010;
        next_hwdata = 32'h0;

        case (sel_i)
            4'b0001: begin
                next_haddr  = {addr_i[31:2], 2'b00};
                next_hsize  = 3'b000;
                next_hwdata = {data_i[7:0], 24'h0};
            end
            4'b0010: begin
                next_haddr  = {addr_i[31:2], 2'b01};
                next_hsize  = 3'b000;
                next_hwdata = {8'h0, data_i[15:8], 16'h0};
            end
            4'b0100: begin
                next_haddr  = {addr_i[31:2], 2'b10};
                next_hsize  = 3'b000;
                next_hwdata = {16'h0, data_i[23:16], 8'h0};
            end
            4'b1000: begin
                next_haddr  = {addr_i[31:2], 2'b11};
                next_hsize  = 3'b000;
                next_hwdata = {24'h0, data_i[31:24]};
            end
            4'b0011: begin
                next_haddr  = {addr_i[31:2], 2'b00};
                next_hsize  = 3'b001;
                next_hwdata = {data_i[7:0], data_i[15:8], 16'h0};
            end
            4'b1100: begin
                next_haddr  = {addr_i[31:2], 2'b10};
                next_hsize  = 3'b001;
                next_hwdata = {16'h0, data_i[23:16], data_i[31:24]};
            end
            4'b1111: begin
                next_haddr  = {addr_i[31:2], 2'b00};
                next_hsize  = 3'b010;
                next_hwdata = {data_i[7:0], data_i[15:8], data_i[23:16], data_i[31:24]};
            end
            default: begin
                sel_valid   = 1'b0;
                next_haddr  = {addr_i[31:2], 2'b00};
                next_hsize  = 3'b000;
                next_hwdata = 32'h0;
            end
        endcase
    end

    always_comb begin
        case (sel_r)
            4'b0001: converted_rdata = {24'h0, hrdata[31:24]};
            4'b0010: converted_rdata = {16'h0, hrdata[23:16], 8'h0};
            4'b0100: converted_rdata = {8'h0, hrdata[15:8], 16'h0};
            4'b1000: converted_rdata = {hrdata[7:0], 24'h0};
            4'b0011: converted_rdata = {16'h0, hrdata[23:16], hrdata[31:24]};
            4'b1100: converted_rdata = {hrdata[7:0], hrdata[15:8], 16'h0};
            4'b1111: converted_rdata = {hrdata[7:0], hrdata[15:8], hrdata[23:16], hrdata[31:24]};
            default: converted_rdata = 32'h0;
        endcase
    end

    always_ff @(posedge hclk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= ST_IDLE;
            sel_r  <= 4'h0;
            htrans <= HTRANS_IDLE;
            hsize  <= 3'b000;
            hwrite <= 1'b0;
            haddr  <= 32'h0;
            hwdata <= 32'h0;
            data_o <= 32'h0;
            ack_o  <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    ack_o  <= 1'b0;
                    htrans <= HTRANS_IDLE;
                    if (cyc_i && stb_i) begin
                        if (sel_valid) begin
                            sel_r  <= sel_i;
                            htrans <= HTRANS_NONSEQ;
                            hsize  <= next_hsize;
                            hwrite <= we_i;
                            haddr  <= next_haddr;
                            hwdata <= we_i ? next_hwdata : 32'h0;
                            state  <= ST_NONSEQ;
                        end else begin
                            sel_r  <= 4'h0;
                            htrans <= HTRANS_IDLE;
                            hsize  <= 3'b000;
                            hwrite <= 1'b0;
                            haddr  <= next_haddr;
                            hwdata <= 32'h0;
                            data_o <= 32'h0;
                            ack_o  <= 1'b1;
                            state  <= ST_ACK;
                        end
                    end
                end

                ST_NONSEQ: begin
                    ack_o <= 1'b0;
                    if (hready) begin
                        htrans <= HTRANS_IDLE;
                        state  <= ST_DATA;
                    end else begin
                        htrans <= HTRANS_NONSEQ;
                    end
                end

                ST_DATA: begin
                    htrans <= HTRANS_IDLE;
                    if (hready) begin
                        if (!hwrite && (hresp == 2'b00)) begin
                            data_o <= converted_rdata;
                        end else begin
                            data_o <= 32'h0;
                        end
                        ack_o <= 1'b1;
                        state <= ST_ACK;
                    end
                end

                ST_ACK: begin
                    ack_o  <= 1'b0;
                    htrans <= HTRANS_IDLE;
                    hwrite <= 1'b0;
                    state  <= ST_IDLE;
                end

                default: begin
                    state  <= ST_IDLE;
                    htrans <= HTRANS_IDLE;
                    ack_o  <= 1'b0;
                end
            endcase
        end
    end

endmodule
