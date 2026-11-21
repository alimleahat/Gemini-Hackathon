module wishbone_to_ahb_bridge (
  // Wishbone Master Interface (Inputs)
  input  logic        clk_i,
  input  logic        rst_i,
  input  logic        cyc_i,
  input  logic        stb_i,
  input  logic [3:0]  sel_i,
  input  logic        we_i,
  input  logic [31:0] addr_i,
  input  logic [31:0] data_i,

  // AHB Slave Interface (Inputs)
  input  logic        hclk,
  input  logic        hreset_n,
  input  logic [31:0] hrdata,
  input  logic [1:0]  hresp,
  input  logic        hready,

  // Wishbone Master Interface (Outputs)
  output logic [31:0] data_o,
  output logic        ack_o,

  // AHB Slave Interface (Outputs)
  output logic [1:0]  htrans,
  output logic [2:0]  hsize,
  output logic [2:0]  hburst,
  output logic        hwrite,
  output logic [31:0] haddr,
  output logic [31:0] hwdata
);

  // AHB Transfer Types (HTRANS)
  localparam logic [1:0] HTRANS_IDLE   = 2'b00;
  localparam logic [1:0] HTRANS_BUSY   = 2'b01;
  localparam logic [1:0] HTRANS_NONSEQ = 2'b10;

  // AHB Transfer Sizes (HSIZE)
  localparam logic [2:0] HSIZE_BYTE     = 3'b000;
  localparam logic [2:0] HSIZE_HALFWORD = 3'b001;
  localparam logic [2:0] HSIZE_WORD     = 3'b010;

  // AHB Burst Type (Single transfer only)
  localparam logic [2:0] HBURST_SINGLE = 3'b000;

  // AHB Response Types (HRESP)
  localparam logic [1:0] HRESP_OKAY  = 2'b00;
  localparam logic [1:0] HRESP_ERROR = 2'b01;
  localparam logic [1:0] HRESP_RETRY = 2'b10;
  localparam logic [1:0] HRESP_SPLIT = 2'b11;

  // FSM States
  localparam logic [1:0] ST_IDLE   = 2'b00;
  localparam logic [1:0] ST_NONSEQ = 2'b01;
  localparam logic [1:0] ST_BUSY   = 2'b10;

  // Combined active-low reset
  logic rst_n;
  assign rst_n = rst_i & hreset_n;

  // Single burst only
  assign hburst = HBURST_SINGLE;

  // Internal registers
  logic [1:0]  state;
  logic [3:0]  sel_reg;
  logic [31:0] wdata_hold;

  // Combinational decode signals
  logic        wb_req;
  logic        sel_valid;
  logic [2:0]  hsize_next;
  logic [1:0]  addr_fix;

  assign wb_req = cyc_i & stb_i & ~ack_o;

  // Endian conversion: Wishbone (little-endian) to AHB (big-endian)
  function automatic logic [31:0] wb_to_ahb_data(
    input logic [31:0] data_in,
    input logic [3:0]  sel
  );
    case (sel)
      4'b0001: wb_to_ahb_data = {data_in[7:0], 24'h0};
      4'b0010: wb_to_ahb_data = {8'h0, data_in[15:8], 16'h0};
      4'b0100: wb_to_ahb_data = {16'h0, data_in[23:16], 8'h0};
      4'b1000: wb_to_ahb_data = {24'h0, data_in[31:24]};
      4'b0011: wb_to_ahb_data = {data_in[7:0], data_in[15:8], 16'h0};
      4'b1100: wb_to_ahb_data = {16'h0, data_in[23:16], data_in[31:24]};
      4'b1111: wb_to_ahb_data = {data_in[7:0], data_in[15:8], data_in[23:16], data_in[31:24]};
      default: wb_to_ahb_data = 32'h0;
    endcase
  endfunction

  // Endian conversion: AHB (big-endian) to Wishbone (little-endian)
  function automatic logic [31:0] ahb_to_wb_data(
    input logic [31:0] data_in,
    input logic [3:0]  sel
  );
    case (sel)
      4'b0001: ahb_to_wb_data = {24'h0, data_in[31:24]};
      4'b0010: ahb_to_wb_data = {16'h0, data_in[23:16], 8'h0};
      4'b0100: ahb_to_wb_data = {8'h0, data_in[15:8], 16'h0};
      4'b1000: ahb_to_wb_data = {data_in[7:0], 24'h0};
      4'b0011: ahb_to_wb_data = {16'h0, data_in[23:16], data_in[31:24]};
      4'b1100: ahb_to_wb_data = {data_in[7:0], data_in[15:8], 16'h0};
      4'b1111: ahb_to_wb_data = {data_in[7:0], data_in[15:8], data_in[23:16], data_in[31:24]};
      default: ahb_to_wb_data = 32'h0;
    endcase
  endfunction

  // Decode transfer size, address offset, and validity from sel_i
  always_comb begin
    sel_valid  = 1'b1;
    hsize_next = HSIZE_BYTE;
    addr_fix   = 2'b00;
    case (sel_i)
      4'b0001: begin
        hsize_next = HSIZE_BYTE;
        addr_fix   = 2'b00;
      end
      4'b0010: begin
        hsize_next = HSIZE_BYTE;
        addr_fix   = 2'b01;
      end
      4'b0100: begin
        hsize_next = HSIZE_BYTE;
        addr_fix   = 2'b10;
      end
      4'b1000: begin
        hsize_next = HSIZE_BYTE;
        addr_fix   = 2'b11;
      end
      4'b0011: begin
        hsize_next = HSIZE_HALFWORD;
        addr_fix   = 2'b00;
      end
      4'b1100: begin
        hsize_next = HSIZE_HALFWORD;
        addr_fix   = 2'b10;
      end
      4'b1111: begin
        hsize_next = HSIZE_WORD;
        addr_fix   = 2'b00;
      end
      default: begin
        sel_valid  = 1'b0;
        hsize_next = HSIZE_BYTE;
        addr_fix   = 2'b00;
      end
    endcase
  end

  // Main FSM and AHB/Wishbone pipeline management
  always_ff @(posedge hclk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= ST_IDLE;
      htrans     <= HTRANS_IDLE;
      hsize      <= HSIZE_BYTE;
      hwrite     <= 1'b0;
      haddr      <= 32'h0;
      hwdata     <= 32'h0;
      data_o     <= 32'h0;
      ack_o      <= 1'b0;
      sel_reg    <= 4'h0;
      wdata_hold <= 32'h0;
    end else begin
      ack_o <= 1'b0;

      case (state)
        ST_IDLE: begin
          htrans <= HTRANS_IDLE;
          if (wb_req) begin
            if (sel_valid) begin
              haddr      <= {addr_i[31:2], addr_fix};
              hsize      <= hsize_next;
              hwrite     <= we_i;
              htrans     <= HTRANS_NONSEQ;
              sel_reg    <= sel_i;
              wdata_hold <= wb_to_ahb_data(data_i, sel_i);
              state      <= ST_NONSEQ;
            end else begin
              // Invalid byte selection: do not issue an AHB transfer to prevent corruption
              htrans     <= HTRANS_IDLE;
              hwrite     <= 1'b0;
              hsize      <= HSIZE_BYTE;
              hwdata     <= 32'h0;
              data_o     <= 32'h0;
              ack_o      <= 1'b1;
              state      <= ST_IDLE;
            end
          end
        end

        ST_NONSEQ: begin
          // Hold address phase signals until AHB slave is ready
          if (hready) begin
            htrans <= HTRANS_IDLE;
            if (hwrite) begin
              hwdata <= wdata_hold;
            end
            state  <= ST_BUSY;
          end
        end

        ST_BUSY: begin
          // Data phase: wait for AHB slave completion
          htrans <= HTRANS_IDLE;
          if (hready) begin
            if ((hresp == HRESP_RETRY) || (hresp == HRESP_SPLIT)) begin
              // Re-issue transfer on RETRY/SPLIT response
              htrans <= HTRANS_NONSEQ;
              state  <= ST_NONSEQ;
            end else begin
              if (!hwrite) begin
                data_o <= (hresp == HRESP_OKAY) ? ahb_to_wb_data(hrdata, sel_reg) : 32'h0;
              end
              ack_o <= (cyc_i & stb_i);
              state <= ST_IDLE;
            end
          end
        end

        default: begin
          state  <= ST_IDLE;
          htrans <= HTRANS_IDLE;
        end
      endcase
    end
  end

endmodule
