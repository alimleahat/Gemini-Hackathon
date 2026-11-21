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

  // Combined active-low reset
  logic rst_n;
  assign rst_n = rst_i & hreset_n;

  // Compact 2-bit FSM state: IDLE=(0,0), NONSEQ=(1,0), BUSY=(0,1)
  logic        st_nonseq;
  logic        st_busy;
  logic [1:0]  hsize_r;
  logic [31:0] wdata_hold;

  // Constant/derived AHB outputs
  assign hburst = 3'b000;
  assign htrans = {st_nonseq, 1'b0};
  assign hsize  = {1'b0, hsize_r};

  // Decode sel_i: validity, transfer size, and address alignment
  logic       sel_valid;
  logic [1:0] hsize_next;
  logic [1:0] addr_fix;

  assign sel_valid     = (~sel_i[3] & ~sel_i[2] & (sel_i[1] | sel_i[0])) |
                         (~sel_i[1] & ~sel_i[0] & (sel_i[3] | sel_i[2])) |
                         (&sel_i);
  assign hsize_next[1] = &sel_i;
  assign hsize_next[0] = (sel_i[1] & sel_i[0] & ~sel_i[3] & ~sel_i[2]) |
                         (sel_i[3] & sel_i[2] & ~sel_i[1] & ~sel_i[0]);
  assign addr_fix[1]   = ~sel_i[0] & ~sel_i[1];
  assign addr_fix[0]   = (~sel_i[0] & sel_i[1]) | (~sel_i[2] & sel_i[3]);

  // Control signals
  logic wb_req_idle;
  logic start_valid;
  logic start_invalid;
  logic hwdata_en;
  logic data_o_en;

  assign wb_req_idle   = ~st_nonseq & ~st_busy & cyc_i & stb_i & ~ack_o;
  assign start_valid   = wb_req_idle & sel_valid;
  assign start_invalid = wb_req_idle & ~sel_valid;
  assign hwdata_en     = start_invalid | (st_nonseq & hready & hwrite);
  assign data_o_en     = start_invalid | (st_busy & hready & ~hresp[1] & ~hwrite);

  // Shared byte enables reconstructed from hsize_r and haddr[1:0]
  // Zeroed in IDLE (invalid sel_i) and on non-OKAY read response in BUSY
  logic       byte_en_active;
  logic [3:0] byte_en;

  assign byte_en_active = st_nonseq | (st_busy & ~hresp[0]);
  assign byte_en[0]     = byte_en_active & ~haddr[1] & ~haddr[0];
  assign byte_en[1]     = byte_en_active & ~haddr[1] & (haddr[0] | hsize_r[0] | hsize_r[1]);
  assign byte_en[2]     = byte_en_active & (hsize_r[1] | (haddr[1] & ~haddr[0]));
  assign byte_en[3]     = byte_en_active & (hsize_r[1] | (haddr[1] & (haddr[0] | hsize_r[0])));

  // Main FSM and AHB/Wishbone pipeline registers
  always_ff @(posedge hclk or negedge rst_n) begin
    if (!rst_n) begin
      st_nonseq  <= 1'b0;
      st_busy    <= 1'b0;
      hsize_r    <= 2'b00;
      hwrite     <= 1'b0;
      haddr      <= 32'h0;
      hwdata     <= 32'h0;
      data_o     <= 32'h0;
      ack_o      <= 1'b0;
      wdata_hold <= 32'h0;
    end else begin
      st_nonseq <= start_valid | (st_nonseq & ~hready) | (st_busy & hready & hresp[1]);
      st_busy   <= (st_nonseq & hready) | (st_busy & ~hready);
      ack_o     <= start_invalid | (st_busy & hready & ~hresp[1] & cyc_i & stb_i);

      if (wb_req_idle) begin
        hsize_r <= hsize_next;
        hwrite  <= sel_valid & we_i;
      end

      if (start_valid) begin
        haddr      <= {addr_i[31:2], addr_fix};
        wdata_hold <= {data_i[7:0], data_i[15:8], data_i[23:16], data_i[31:24]};
      end

      if (hwdata_en) begin
        hwdata <= {
          {8{byte_en[0]}} & wdata_hold[31:24],
          {8{byte_en[1]}} & wdata_hold[23:16],
          {8{byte_en[2]}} & wdata_hold[15:8],
          {8{byte_en[3]}} & wdata_hold[7:0]
        };
      end

      if (data_o_en) begin
        data_o <= {
          {8{byte_en[3]}} & hrdata[7:0],
          {8{byte_en[2]}} & hrdata[15:8],
          {8{byte_en[1]}} & hrdata[23:16],
          {8{byte_en[0]}} & hrdata[31:24]
        };
      end
    end
  end

endmodule
