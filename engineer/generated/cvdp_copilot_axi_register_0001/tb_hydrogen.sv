`timescale 1ns/1ps

module tb;

  // Parameters for primary DUT
  localparam integer ADDR_WIDTH = 32;
  localparam integer DATA_WIDTH = 32;
  localparam integer STRB_WIDTH = DATA_WIDTH / 8;

  // Register offsets
  localparam [ADDR_WIDTH-1:0] ADDR_BEAT      = 32'h0000_0100;
  localparam [ADDR_WIDTH-1:0] ADDR_START     = 32'h0000_0200;
  localparam [ADDR_WIDTH-1:0] ADDR_DONE      = 32'h0000_0300;
  localparam [ADDR_WIDTH-1:0] ADDR_WRITEBACK = 32'h0000_0400;
  localparam [ADDR_WIDTH-1:0] ADDR_ID        = 32'h0000_0500;

  // AXI response codes
  localparam [1:0] RESP_OKAY   = 2'b00;
  localparam [1:0] RESP_SLVERR = 2'b10;

  // Expected fixed ID
  localparam [31:0] FIXED_ID = 32'h0001_0001;

  // Clock and reset
  reg clk_i;
  reg rst_n_i;

  // Primary DUT signals
  reg  [ADDR_WIDTH-1:0] awaddr_i;
  reg                   awvalid_i;
  wire                  awready_o;
  reg  [DATA_WIDTH-1:0] wdata_i;
  reg                   wvalid_i;
  reg  [STRB_WIDTH-1:0] wstrb_i;
  wire                  wready_o;
  wire [1:0]            bresp_o;
  wire                  bvalid_o;
  reg                   bready_i;
  reg  [ADDR_WIDTH-1:0] araddr_i;
  reg                   arvalid_i;
  wire                  arready_o;
  wire [DATA_WIDTH-1:0] rdata_o;
  wire                  rvalid_o;
  wire [1:0]            rresp_o;
  reg                   rready_i;
  reg                   done_i;
  wire [19:0]           beat_o;
  wire                  start_o;
  wire                  writeback_o;

  // Secondary DUT signals (ADDR_WIDTH = 12)
  localparam integer NARROW_AW = 12;
  reg                   n_rst_n_i;
  reg  [NARROW_AW-1:0]  n_awaddr_i;
  reg                   n_awvalid_i;
  wire                  n_awready_o;
  reg  [DATA_WIDTH-1:0] n_wdata_i;
  reg                   n_wvalid_i;
  reg  [STRB_WIDTH-1:0] n_wstrb_i;
  wire                  n_wready_o;
  wire [1:0]            n_bresp_o;
  wire                  n_bvalid_o;
  reg                   n_bready_i;
  reg  [NARROW_AW-1:0]  n_araddr_i;
  reg                   n_arvalid_i;
  wire                  n_arready_o;
  wire [DATA_WIDTH-1:0] n_rdata_o;
  wire                  n_rvalid_o;
  wire [1:0]            n_rresp_o;
  reg                   n_rready_i;
  reg                   n_done_i;
  wire [19:0]           n_beat_o;
  wire                  n_start_o;
  wire                  n_writeback_o;

  integer errors = 0;

  // Primary DUT instantiation
  axi_register #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk_i       (clk_i),
    .rst_n_i     (rst_n_i),
    .awaddr_i    (awaddr_i),
    .awvalid_i   (awvalid_i),
    .awready_o   (awready_o),
    .wdata_i     (wdata_i),
    .wvalid_i    (wvalid_i),
    .wstrb_i     (wstrb_i),
    .wready_o    (wready_o),
    .bresp_o     (bresp_o),
    .bvalid_o    (bvalid_o),
    .bready_i    (bready_i),
    .araddr_i    (araddr_i),
    .arvalid_i   (arvalid_i),
    .arready_o   (arready_o),
    .rdata_o     (rdata_o),
    .rvalid_o    (rvalid_o),
    .rresp_o     (rresp_o),
    .rready_i    (rready_i),
    .done_i      (done_i),
    .beat_o      (beat_o),
    .start_o     (start_o),
    .writeback_o (writeback_o)
  );

  // Secondary DUT instantiation (minimum ADDR_WIDTH = 12)
  axi_register #(
    .ADDR_WIDTH(NARROW_AW),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut_narrow (
    .clk_i       (clk_i),
    .rst_n_i     (n_rst_n_i),
    .awaddr_i    (n_awaddr_i),
    .awvalid_i   (n_awvalid_i),
    .awready_o   (n_awready_o),
    .wdata_i     (n_wdata_i),
    .wvalid_i    (n_wvalid_i),
    .wstrb_i     (n_wstrb_i),
    .wready_o    (n_wready_o),
    .bresp_o     (n_bresp_o),
    .bvalid_o    (n_bvalid_o),
    .bready_i    (n_bready_i),
    .araddr_i    (n_araddr_i),
    .arvalid_i   (n_arvalid_i),
    .arready_o   (n_arready_o),
    .rdata_o     (n_rdata_o),
    .rvalid_o    (n_rvalid_o),
    .rresp_o     (n_rresp_o),
    .rready_i    (n_rready_i),
    .done_i      (n_done_i),
    .beat_o      (n_beat_o),
    .start_o     (n_start_o),
    .writeback_o (n_writeback_o)
  );

  // 100 MHz clock generation
  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  // Helper check task
  task check_eq_32;
    input [255:0] label;
    input [31:0]  got;
    input [31:0]  exp;
    begin
      if (got !== exp) begin
        $display("FAIL: %0s - expected 0x%08h, got 0x%08h (time %0t)", label, exp, got, $time);
        errors = errors + 1;
      end
    end
  endtask

  task check_eq_20;
    input [255:0] label;
    input [19:0]  got;
    input [19:0]  exp;
    begin
      if (got !== exp) begin
        $display("FAIL: %0s - expected 0x%05h, got 0x%05h (time %0t)", label, exp, got, $time);
        errors = errors + 1;
      end
    end
  endtask

  task check_eq_2;
    input [255:0] label;
    input [1:0]   got;
    input [1:0]   exp;
    begin
      if (got !== exp) begin
        $display("FAIL: %0s - expected 2'b%02b, got 2'b%02b (time %0t)", label, exp, got, $time);
        errors = errors + 1;
      end
    end
  endtask

  task check_eq_1;
    input [255:0] label;
    input         got;
    input         exp;
    begin
      if (got !== exp) begin
        $display("FAIL: %0s - expected %0b, got %0b (time %0t)", label, exp, got, $time);
        errors = errors + 1;
      end
    end
  endtask

  // AXI4-Lite Write Task (supports sequential AW->W, W->AW, or simultaneous AW+W)
  task axi_write;
    input  [ADDR_WIDTH-1:0] addr;
    input  [DATA_WIDTH-1:0] data;
    input  [STRB_WIDTH-1:0] strb;
    input  [1:0]            exp_resp;
    input  integer          bready_delay;
    integer cyc;
    reg aw_done;
    reg w_done;
    reg b_done;
    reg [1:0] cap_bresp;
    begin
      aw_done = 1'b0;
      w_done  = 1'b0;
      b_done  = 1'b0;

      @(posedge clk_i);
      awaddr_i  <= addr;
      awvalid_i <= 1'b1;
      wdata_i   <= data;
      wstrb_i   <= strb;
      wvalid_i  <= 1'b1;
      bready_i  <= (bready_delay == 0) ? 1'b1 : 1'b0;

      cyc = 0;
      while (!(aw_done && w_done) && cyc < 50) begin
        @(posedge clk_i);
        cyc = cyc + 1;
        if (!aw_done && awvalid_i && awready_o) begin
          aw_done   = 1'b1;
          awvalid_i <= 1'b0;
        end
        if (!w_done && wvalid_i && wready_o) begin
          w_done   = 1'b1;
          wvalid_i <= 1'b0;
        end
        if (bvalid_o && bready_i) begin
          b_done    = 1'b1;
          cap_bresp = bresp_o;
          bready_i  <= 1'b0;
        end
      end

      if (!(aw_done && w_done)) begin
        $display("FAIL: axi_write addr=0x%08h timed out in AW/W phase (aw_done=%0b w_done=%0b)", addr, aw_done, w_done);
        errors = errors + 1;
        awvalid_i <= 1'b0;
        wvalid_i  <= 1'b0;
        bready_i  <= 1'b0;
      end else begin
        // Wait for BVALID if not already received
        cyc = 0;
        while (!bvalid_o && !b_done && cyc < 50) begin
          @(posedge clk_i);
          cyc = cyc + 1;
        end

        if (!bvalid_o && !b_done) begin
          $display("FAIL: axi_write addr=0x%08h timed out waiting for bvalid_o", addr);
          errors = errors + 1;
          bready_i <= 1'b0;
        end else if (!b_done) begin
          // Apply bready backpressure if requested and verify bvalid_o/bresp_o hold steady
          cap_bresp = bresp_o;
          if (bready_delay > 0) begin
            for (cyc = 0; cyc < bready_delay; cyc = cyc + 1) begin
              if (bvalid_o !== 1'b1) begin
                $display("FAIL: bvalid_o dropped prematurely before bready_i at addr=0x%08h", addr);
                errors = errors + 1;
              end
              if (bresp_o !== cap_bresp) begin
                $display("FAIL: bresp_o changed while waiting for bready_i at addr=0x%08h", addr);
                errors = errors + 1;
              end
              @(posedge clk_i);
            end
            bready_i <= 1'b1;
            // Wait for handshake cycle
            cyc = 0;
            while (!(bvalid_o && bready_i) && cyc < 10) begin
              @(posedge clk_i);
              cyc = cyc + 1;
            end
            cap_bresp = bresp_o;
            bready_i <= 1'b0;
          end else begin
            // bready_i was already 1
            cyc = 0;
            while (!(bvalid_o && bready_i) && cyc < 10) begin
              @(posedge clk_i);
              cyc = cyc + 1;
            end
            cap_bresp = bresp_o;
            bready_i <= 1'b0;
          end

          @(posedge clk_i);
          if (bvalid_o !== 1'b0) begin
            $display("FAIL: bvalid_o did not deassert after B handshake at addr=0x%08h", addr);
            errors = errors + 1;
          end
        end

        if (cap_bresp !== exp_resp) begin
          $display("FAIL: axi_write addr=0x%08h bresp mismatch - expected 2'b%02b, got 2'b%02b", addr, exp_resp, cap_bresp);
          errors = errors + 1;
        end
      end
    end
  endtask

  // Staggered Write Task (AW first, idle gap, then W)
  task axi_write_staggered;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] data;
    input [STRB_WIDTH-1:0] strb;
    input [1:0]            exp_resp;
    integer cyc;
    reg [1:0] cap_bresp;
    begin
      @(posedge clk_i);
      awaddr_i  <= addr;
      awvalid_i <= 1'b1;

      cyc = 0;
      @(posedge clk_i);
      while (!(awvalid_i && awready_o) && cyc < 50) begin
        @(posedge clk_i);
        cyc = cyc + 1;
      end
      if (!(awvalid_i && awready_o)) begin
        $display("FAIL: axi_write_staggered AW timeout addr=0x%08h", addr);
        errors = errors + 1;
      end
      awvalid_i <= 1'b0;

      // Insert 3 idle cycles before W phase
      repeat (3) @(posedge clk_i);

      wdata_i  <= data;
      wstrb_i  <= strb;
      wvalid_i <= 1'b1;
      bready_i <= 1'b1;

      cyc = 0;
      @(posedge clk_i);
      while (!(wvalid_i && wready_o) && cyc < 50) begin
        @(posedge clk_i);
        cyc = cyc + 1;
      end
      if (!(wvalid_i && wready_o)) begin
        $display("FAIL: axi_write_staggered W timeout addr=0x%08h", addr);
        errors = errors + 1;
      end
      wvalid_i <= 1'b0;

      cyc = 0;
      while (!(bvalid_o && bready_i) && cyc < 50) begin
        @(posedge clk_i);
        cyc = cyc + 1;
      end
      if (!(bvalid_o && bready_i)) begin
        $display("FAIL: axi_write_staggered B timeout addr=0x%08h", addr);
        errors = errors + 1;
      end else begin
        cap_bresp = bresp_o;
        if (cap_bresp !== exp_resp) begin
          $display("FAIL: axi_write_staggered bresp mismatch - expected 2'b%02b, got 2'b%02b", exp_resp, cap_bresp);
          errors = errors + 1;
        end
      end
      bready_i <= 1'b0;
      @(posedge clk_i);
    end
  endtask

  // AXI4-Lite Read Task
  task axi_read;
    input  [ADDR_WIDTH-1:0] addr;
    output [DATA_WIDTH-1:0] data_out;
    input  [1:0]            exp_resp;
    input  integer          rready_delay;
    integer cyc;
    reg [1:0] cap_rresp;
    begin
      @(posedge clk_i);
      araddr_i  <= addr;
      arvalid_i <= 1'b1;
      rready_i  <= (rready_delay == 0) ? 1'b1 : 1'b0;

      cyc = 0;
      @(posedge clk_i);
      while (!(arvalid_i && arready_o) && cyc < 50) begin
        @(posedge clk_i);
        cyc = cyc + 1;
      end

      if (!(arvalid_i && arready_o)) begin
        $display("FAIL: axi_read addr=0x%08h timed out waiting for arready_o", addr);
        errors = errors + 1;
        arvalid_i <= 1'b0;
        rready_i  <= 1'b0;
        data_out  = {DATA_WIDTH{1'bx}};
      end else begin
        arvalid_i <= 1'b0;

        cyc = 0;
        while (!rvalid_o && cyc < 50) begin
          @(posedge clk_i);
          cyc = cyc + 1;
        end

        if (!rvalid_o) begin
          $display("FAIL: axi_read addr=0x%08h timed out waiting for rvalid_o", addr);
          errors = errors + 1;
          rready_i <= 1'b0;
          data_out = {DATA_WIDTH{1'bx}};
        end else begin
          data_out  = rdata_o;
          cap_rresp = rresp_o;

          if (rready_delay > 0) begin
            for (cyc = 0; cyc < rready_delay; cyc = cyc + 1) begin
              if (rvalid_o !== 1'b1) begin
                $display("FAIL: rvalid_o dropped prematurely before rready_i at addr=0x%08h", addr);
                errors = errors + 1;
              end
              if (rdata_o !== data_out || rresp_o !== cap_rresp) begin
                $display("FAIL: rdata_o/rresp_o changed while waiting for rready_i at addr=0x%08h", addr);
                errors = errors + 1;
              end
              @(posedge clk_i);
            end
            rready_i <= 1'b1;
            cyc = 0;
            while (!(rvalid_o && rready_i) && cyc < 10) begin
              @(posedge clk_i);
              cyc = cyc + 1;
            end
            data_out  = rdata_o;
            cap_rresp = rresp_o;
            rready_i  <= 1'b0;
          end else begin
            cyc = 0;
            while (!(rvalid_o && rready_i) && cyc < 10) begin
              @(posedge clk_i);
              cyc = cyc + 1;
            end
            data_out  = rdata_o;
            cap_rresp = rresp_o;
            rready_i  <= 1'b0;
          end

          @(posedge clk_i);
          if (rvalid_o !== 1'b0) begin
            $display("FAIL: rvalid_o did not deassert after R handshake at addr=0x%08h", addr);
            errors = errors + 1;
          end

          if (cap_rresp !== exp_resp) begin
            $display("FAIL: axi_read addr=0x%08h rresp mismatch - expected 2'b%02b, got 2'b%02b", addr, exp_resp, cap_rresp);
            errors = errors + 1;
          end
        end
      end
    end
  endtask

  // Narrow DUT tasks (ADDR_WIDTH=12)
  task narrow_write;
    input [NARROW_AW-1:0]  addr;
    input [DATA_WIDTH-1:0] data;
    input [STRB_WIDTH-1:0] strb;
    input [1:0]            exp_resp;
    integer cyc;
    reg aw_done, w_done;
    begin
      aw_done = 1'b0;
      w_done  = 1'b0;
      @(posedge clk_i);
      n_awaddr_i  <= addr;
      n_awvalid_i <= 1'b1;
      n_wdata_i   <= data;
      n_wstrb_i   <= strb;
      n_wvalid_i  <= 1'b1;
      n_bready_i  <= 1'b1;

      cyc = 0;
      while (!(aw_done && w_done) && cyc < 50) begin
        @(posedge clk_i);
        cyc = cyc + 1;
        if (!aw_done && n_awvalid_i && n_awready_o) begin
          aw_done = 1'b1;
          n_awvalid_i <= 1'b0;
        end
        if (!w_done && n_wvalid_i && n_wready_o) begin
          w_done = 1'b1;
          n_wvalid_i <= 1'b0;
        end
      end

      cyc = 0;
      while (!(n_bvalid_o && n_bready_i) && cyc < 50) begin
        @(posedge clk_i);
        cyc = cyc + 1;
      end
      if (!(n_bvalid_o && n_bready_i)) begin
        $display("FAIL: narrow_write timeout addr=0x%03h", addr);
        errors = errors + 1;
      end else if (n_bresp_o !== exp_resp) begin
        $display("FAIL: narrow_write bresp mismatch addr=0x%03h - expected 2'b%02b, got 2'b%02b", addr, exp_resp, n_bresp_o);
        errors = errors + 1;
      end
      n_bready_i <= 1'b0;
      @(posedge clk_i);
    end
  endtask

  task narrow_read;
    input  [NARROW_AW-1:0]  addr;
    output [DATA_WIDTH-1:0] data_out;
    input  [1:0]            exp_resp;
    integer cyc;
    begin
      @(posedge clk_i);
      n_araddr_i  <= addr;
      n_arvalid_i <= 1'b1;
      n_rready_i  <= 1'b1;

      cyc = 0;
      @(posedge clk_i);
      while (!(n_arvalid_i && n_arready_o) && cyc < 50) begin
        @(posedge clk_i);
        cyc = cyc + 1;
      end
      n_arvalid_i <= 1'b0;

      cyc = 0;
      while (!(n_rvalid_o && n_rready_i) && cyc < 50) begin
        @(posedge clk_i);
        cyc = cyc + 1;
      end
      if (!(n_rvalid_o && n_rready_i)) begin
        $display("FAIL: narrow_read timeout addr=0x%03h", addr);
        errors = errors + 1;
        data_out = {DATA_WIDTH{1'bx}};
      end else begin
        data_out = n_rdata_o;
        if (n_rresp_o !== exp_resp) begin
          $display("FAIL: narrow_read rresp mismatch addr=0x%03h - expected 2'b%02b, got 2'b%02b", addr, exp_resp, n_rresp_o);
          errors = errors + 1;
        end
      end
      n_rready_i <= 1'b0;
      @(posedge clk_i);
    end
  endtask

  // Main test sequence
  reg [DATA_WIDTH-1:0] rdata;

  initial begin
    // Initialize all inputs
    rst_n_i     = 1'b0;
    awaddr_i    = {ADDR_WIDTH{1'b0}};
    awvalid_i   = 1'b0;
    wdata_i     = {DATA_WIDTH{1'b0}};
    wvalid_i    = 1'b0;
    wstrb_i     = {STRB_WIDTH{1'b0}};
    bready_i    = 1'b0;
    araddr_i    = {ADDR_WIDTH{1'b0}};
    arvalid_i   = 1'b0;
    rready_i    = 1'b0;
    done_i      = 1'b0;

    n_rst_n_i   = 1'b0;
    n_awaddr_i  = {NARROW_AW{1'b0}};
    n_awvalid_i = 1'b0;
    n_wdata_i   = {DATA_WIDTH{1'b0}};
    n_wvalid_i  = 1'b0;
    n_wstrb_i   = {STRB_WIDTH{1'b0}};
    n_bready_i  = 1'b0;
    n_araddr_i  = {NARROW_AW{1'b0}};
    n_arvalid_i = 1'b0;
    n_rready_i  = 1'b0;
    n_done_i    = 1'b0;

    // ---------------------------------------------------------
    // Test 1: Reset Behavior & Initial Register Reads
    // ---------------------------------------------------------
    repeat (3) @(posedge clk_i);
    #1;
    check_eq_20("Reset beat_o",      beat_o,      20'h00000);
    check_eq_1 ("Reset start_o",     start_o,     1'b0);
    check_eq_1 ("Reset writeback_o", writeback_o, 1'b0);
    check_eq_1 ("Reset bvalid_o",    bvalid_o,    1'b0);
    check_eq_1 ("Reset rvalid_o",    rvalid_o,    1'b0);

    @(posedge clk_i);
    rst_n_i   <= 1'b1;
    n_rst_n_i <= 1'b1;
    repeat (2) @(posedge clk_i);

    axi_read(ADDR_BEAT,      rdata, RESP_OKAY, 0); check_eq_32("Post-reset Beat",      rdata, 32'h0000_0000);
    axi_read(ADDR_START,     rdata, RESP_OKAY, 0); check_eq_32("Post-reset Start",     rdata, 32'h0000_0000);
    axi_read(ADDR_DONE,      rdata, RESP_OKAY, 0); check_eq_32("Post-reset Done",      rdata, 32'h0000_0000);
    axi_read(ADDR_WRITEBACK, rdata, RESP_OKAY, 0); check_eq_32("Post-reset Writeback", rdata, 32'h0000_0000);
    axi_read(ADDR_ID,        rdata, RESP_OKAY, 0); check_eq_32("Post-reset ID",        rdata, FIXED_ID);

    // ---------------------------------------------------------
    // Test 2: Beat Register R/W & 20-bit Boundary Values
    // ---------------------------------------------------------
    axi_write(ADDR_BEAT, 32'h0000_5678, 4'b1111, RESP_OKAY, 0);
    check_eq_20("Beat write 0x05678", beat_o, 20'h05678);
    axi_read(ADDR_BEAT, rdata, RESP_OKAY, 0);
    check_eq_32("Beat read 0x05678", rdata, 32'h0000_5678);

    // Upper 12 bits must be ignored/zero-padded
    axi_write(ADDR_BEAT, 32'hFFFF_FFFF, 4'b1111, RESP_OKAY, 0);
    check_eq_20("Beat write 0xFFFFF", beat_o, 20'hFFFFF);
    axi_read(ADDR_BEAT, rdata, RESP_OKAY, 0);
    check_eq_32("Beat read 0x000FFFFF", rdata, 32'h000F_FFFF);

    axi_write(ADDR_BEAT, 32'h0000_0000, 4'b1111, RESP_OKAY, 0);
    check_eq_20("Beat write 0x00000", beat_o, 20'h00000);

    axi_write(ADDR_BEAT, 32'hABCD_1234, 4'b1111, RESP_OKAY, 0);
    check_eq_20("Beat write 0xD1234", beat_o, 20'hD1234);
    axi_read(ADDR_BEAT, rdata, RESP_OKAY, 0);
    check_eq_32("Beat read 0x000D1234", rdata, 32'h000D_1234);

    // ---------------------------------------------------------
    // Test 3: Start & Writeback Control Registers
    // ---------------------------------------------------------
    axi_write(ADDR_START, 32'h0000_0001, 4'b1111, RESP_OKAY, 0);
    check_eq_1("Start set to 1", start_o, 1'b1);
    axi_read(ADDR_START, rdata, RESP_OKAY, 0);
    check_eq_32("Start read 1", rdata, 32'h0000_0001);

    axi_write(ADDR_START, 32'h0000_0000, 4'b1111, RESP_OKAY, 0);
    check_eq_1("Start cleared to 0", start_o, 1'b0);
    axi_read(ADDR_START, rdata, RESP_OKAY, 0);
    check_eq_32("Start read 0", rdata, 32'h0000_0000);

    axi_write(ADDR_START, 32'hFFFF_FFFE, 4'b1111, RESP_OKAY, 0);
    check_eq_1("Start write LSB=0", start_o, 1'b0);

    axi_write(ADDR_WRITEBACK, 32'h0000_0001, 4'b1111, RESP_OKAY, 0);
    check_eq_1("Writeback set to 1", writeback_o, 1'b1);
    axi_read(ADDR_WRITEBACK, rdata, RESP_OKAY, 0);
    check_eq_32("Writeback read 1", rdata, 32'h0000_0001);

    axi_write(ADDR_WRITEBACK, 32'h0000_0000, 4'b1111, RESP_OKAY, 0);
    check_eq_1("Writeback cleared to 0", writeback_o, 1'b0);
    axi_read(ADDR_WRITEBACK, rdata, RESP_OKAY, 0);
    check_eq_32("Writeback read 0", rdata, 32'h0000_0000);

    // Verify Beat remained intact
    check_eq_20("Beat undisturbed after Start/WB", beat_o, 20'hD1234);

    // ---------------------------------------------------------
    // Test 4: Done Status Register (done_i & W1C)
    // ---------------------------------------------------------
    @(posedge clk_i);
    done_i <= 1'b1;
    repeat (2) @(posedge clk_i);
    axi_read(ADDR_DONE, rdata, RESP_OKAY, 0);
    check_eq_32("Done read while done_i=1", rdata, 32'h0000_0001);

    @(posedge clk_i);
    done_i <= 1'b0;
    repeat (2) @(posedge clk_i);
    axi_read(ADDR_DONE, rdata, RESP_OKAY, 0);
    check_eq_32("Done latched after done_i=0", rdata, 32'h0000_0001);

    // Writing 0 must not clear Done
    axi_write(ADDR_DONE, 32'h0000_0000, 4'b1111, RESP_OKAY, 0);
    axi_read(ADDR_DONE, rdata, RESP_OKAY, 0);
    check_eq_32("Done remains 1 after writing 0", rdata, 32'h0000_0001);

    // Writing 1 clears Done
    axi_write(ADDR_DONE, 32'h0000_0001, 4'b1111, RESP_OKAY, 0);
    axi_read(ADDR_DONE, rdata, RESP_OKAY, 0);
    check_eq_32("Done cleared after writing 1", rdata, 32'h0000_0000);

    // ---------------------------------------------------------
    // Test 5: Partial Writes (wstrb_i != 4'b1111 leaves register unchanged)
    // ---------------------------------------------------------
    axi_write(ADDR_BEAT, 32'h0005_4321, 4'b1111, RESP_OKAY, 0);
    check_eq_20("Beat setup for partial write", beat_o, 20'h54321);

    axi_write(ADDR_BEAT, 32'h0009_9999, 4'b0111, RESP_OKAY, 0);
    check_eq_20("Beat unchanged on wstrb=4'b0111", beat_o, 20'h54321);

    axi_write(ADDR_BEAT, 32'h0008_8888, 4'b1110, RESP_OKAY, 0);
    check_eq_20("Beat unchanged on wstrb=4'b1110", beat_o, 20'h54321);

    axi_write(ADDR_BEAT, 32'h0007_7777, 4'b0000, RESP_OKAY, 0);
    check_eq_20("Beat unchanged on wstrb=4'b0000", beat_o, 20'h54321);

    axi_write(ADDR_START, 32'h0000_0001, 4'b1110, RESP_OKAY, 0);
    check_eq_1("Start unchanged on wstrb=4'b1110", start_o, 1'b0);

    axi_write(ADDR_START, 32'h0000_0001, 4'b0000, RESP_OKAY, 0);
    check_eq_1("Start unchanged on wstrb=4'b0000", start_o, 1'b0);

    axi_write(ADDR_WRITEBACK, 32'h0000_0001, 4'b1110, RESP_OKAY, 0);
    check_eq_1("Writeback unchanged on wstrb=4'b1110", writeback_o, 1'b0);

    axi_write(ADDR_WRITEBACK, 32'h0000_0001, 4'b0000, RESP_OKAY, 0);
    check_eq_1("Writeback unchanged on wstrb=4'b0000", writeback_o, 1'b0);

    // ---------------------------------------------------------
    // Test 6: Read-Only ID Register & Invalid Address SLVERR
    // ---------------------------------------------------------
    axi_write(ADDR_ID, 32'hDEAD_BEEF, 4'b1111, RESP_SLVERR, 0);
    axi_read(ADDR_ID, rdata, RESP_OKAY, 0);
    check_eq_32("ID unchanged after write attempt", rdata, FIXED_ID);

    // Invalid write addresses
    axi_write(32'h0000_0000, 32'h1234_5678, 4'b1111, RESP_SLVERR, 0);
    axi_write(32'h0000_0104, 32'h1234_5678, 4'b1111, RESP_SLVERR, 0);
    axi_write(32'h0000_0208, 32'h1234_5678, 4'b1111, RESP_SLVERR, 0);
    axi_write(32'h0000_0600, 32'h1234_5678, 4'b1111, RESP_SLVERR, 0);
    axi_write(32'h0000_0FFC, 32'h1234_5678, 4'b1111, RESP_SLVERR, 0);

    // Invalid read addresses
    axi_read(32'h0000_0000, rdata, RESP_SLVERR, 0);
    axi_read(32'h0000_0104, rdata, RESP_SLVERR, 0);
    axi_read(32'h0000_0208, rdata, RESP_SLVERR, 0);
    axi_read(32'h0000_0600, rdata, RESP_SLVERR, 0);
    axi_read(32'h0000_0FFC, rdata, RESP_SLVERR, 0);

    // ---------------------------------------------------------
    // Test 7: Flow Control, Backpressure & Staggered Phases
    // ---------------------------------------------------------
    axi_write_staggered(ADDR_BEAT, 32'h0003_C3C3, 4'b1111, RESP_OKAY);
    check_eq_20("Staggered write Beat", beat_o, 20'h3C3C3);

    // Write with bready_i delayed by 4 cycles
    axi_write(ADDR_BEAT, 32'h000A_5A5A, 4'b1111, RESP_OKAY, 4);
    check_eq_20("Backpressured write Beat", beat_o, 20'hA5A5A);

    // Read with rready_i delayed by 4 cycles
    axi_read(ADDR_BEAT, rdata, RESP_OKAY, 4);
    check_eq_32("Backpressured read Beat", rdata, 32'h000A_5A5A);

    // Back-to-back read of ID with delay
    axi_read(ADDR_ID, rdata, RESP_OKAY, 3);
    check_eq_32("Backpressured read ID", rdata, FIXED_ID);

    // ---------------------------------------------------------
    // Test 8: Asynchronous Mid-Operation Reset
    // ---------------------------------------------------------
    axi_write(ADDR_BEAT,      32'h000A_BCDE, 4'b1111, RESP_OKAY, 0);
    axi_write(ADDR_START,     32'h0000_0001, 4'b1111, RESP_OKAY, 0);
    axi_write(ADDR_WRITEBACK, 32'h0000_0001, 4'b1111, RESP_OKAY, 0);
    @(posedge clk_i);
    done_i <= 1'b1;
    @(posedge clk_i);
    done_i <= 1'b0;
    @(negedge clk_i);
    // Assert async reset mid-cycle
    rst_n_i = 1'b0;
    #1;
    check_eq_20("Async reset beat_o",      beat_o,      20'h00000);
    check_eq_1 ("Async reset start_o",     start_o,     1'b0);
    check_eq_1 ("Async reset writeback_o", writeback_o, 1'b0);
    check_eq_1 ("Async reset bvalid_o",    bvalid_o,    1'b0);
    check_eq_1 ("Async reset rvalid_o",    rvalid_o,    1'b0);

    repeat (2) @(posedge clk_i);
    rst_n_i <= 1'b1;
    repeat (2) @(posedge clk_i);

    axi_read(ADDR_BEAT,      rdata, RESP_OKAY, 0); check_eq_32("Post-async-reset Beat",      rdata, 32'h0000_0000);
    axi_read(ADDR_START,     rdata, RESP_OKAY, 0); check_eq_32("Post-async-reset Start",     rdata, 32'h0000_0000);
    axi_read(ADDR_DONE,      rdata, RESP_OKAY, 0); check_eq_32("Post-async-reset Done",      rdata, 32'h0000_0000);
    axi_read(ADDR_WRITEBACK, rdata, RESP_OKAY, 0); check_eq_32("Post-async-reset Writeback", rdata, 32'h0000_0000);
    axi_read(ADDR_ID,        rdata, RESP_OKAY, 0); check_eq_32("Post-async-reset ID",        rdata, FIXED_ID);

    // ---------------------------------------------------------
    // Test 9: Parameterized Instance (ADDR_WIDTH = 12)
    // ---------------------------------------------------------
    narrow_write(12'h100, 32'h0001_2345, 4'b1111, RESP_OKAY);
    check_eq_20("Narrow DUT beat_o", n_beat_o, 20'h12345);
    narrow_read(12'h100, rdata, RESP_OKAY);
    check_eq_32("Narrow DUT Beat read", rdata, 32'h0001_2345);
    narrow_read(12'h500, rdata, RESP_OKAY);
    check_eq_32("Narrow DUT ID read", rdata, FIXED_ID);
    narrow_write(12'h500, 32'hAAAA_BBBB, 4'b1111, RESP_SLVERR);
    narrow_read(12'h700, rdata, RESP_SLVERR);

    // ---------------------------------------------------------
    // Summary
    // ---------------------------------------------------------
    repeat (4) @(posedge clk_i);
    if (errors == 0) begin
      $display("PASS");
    end else begin
      $display("FAIL: %0d errors", errors);
    end
    $finish;
  end

endmodule
