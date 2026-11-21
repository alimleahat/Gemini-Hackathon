`timescale 1ns/1ps

module tb;

  // Clock and Reset signals
  reg         clk;
  wire        clk_i;
  wire        hclk;
  reg         rst_i;
  reg         hreset_n;

  // Wishbone Master signals
  reg         cyc_i;
  reg         stb_i;
  reg  [3:0]  sel_i;
  reg         we_i;
  reg  [31:0] addr_i;
  reg  [31:0] data_i;
  wire [31:0] data_o;
  wire        ack_o;

  // AHB Slave signals
  reg  [31:0] hrdata;
  reg  [1:0]  hresp;
  reg         hready;
  wire [1:0]  htrans;
  wire [2:0]  hsize;
  wire [2:0]  hburst;
  wire        hwrite;
  wire [31:0] haddr;
  wire [31:0] hwdata;

  assign clk_i = clk;
  assign hclk  = clk;

  // DUT Instantiation
  wishbone_to_ahb_bridge dut (
    .clk_i    (clk_i),
    .rst_i    (rst_i),
    .cyc_i    (cyc_i),
    .stb_i    (stb_i),
    .sel_i    (sel_i),
    .we_i     (we_i),
    .addr_i   (addr_i),
    .data_i   (data_i),
    .hclk     (hclk),
    .hreset_n (hreset_n),
    .hrdata   (hrdata),
    .hresp    (hresp),
    .hready   (hready),
    .data_o   (data_o),
    .ack_o    (ack_o),
    .htrans   (htrans),
    .hsize    (hsize),
    .hburst   (hburst),
    .hwrite   (hwrite),
    .haddr    (haddr),
    .hwdata   (hwdata)
  );

  // Error counter and testbench control
  integer errors = 0;
  integer i;

  // Endianness calibration flags
  reg byte_swap;
  reg endian_calibrated;
  reg be_addr_inv;
  reg be_addr_calibrated;

  // AHB Slave Memory (256 x 32-bit words)
  reg [31:0] slave_mem [0:255];

  // AHB Slave internal pipeline state
  reg        dp_active;
  reg [31:0] dp_addr;
  reg [2:0]  dp_size;
  reg        dp_write;
  integer    slave_wait_cycles;
  integer    wait_cnt;
  reg        force_addr_stall;

  // Protocol monitor state
  reg        prev_stalled_ap;
  reg [31:0] held_haddr;
  reg [2:0]  held_hsize;
  reg        held_hwrite;
  reg [2:0]  held_hburst;
  reg        check_hwdata_hold;
  reg [31:0] held_hwdata;
  reg        expect_valid_tx;
  reg [3:0]  active_sel;
  reg [31:0] active_wb_addr;
  reg        ahb_seen_nonseq;

  // Clock generation (10ns period)
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // Watchdog timeout
  initial begin
    #100000;
    $display("FAIL: Global watchdog timeout reached");
    errors = errors + 1;
    $display("FAIL: %0d errors", errors);
    $finish;
  end

  // Helper task to compute expected hsize from sel_i
  function [2:0] exp_hsize_from_sel;
    input [3:0] sel;
    begin
      case (sel)
        4'b0001, 4'b0010, 4'b0100, 4'b1000: exp_hsize_from_sel = 3'b000;
        4'b0011, 4'b1100:                   exp_hsize_from_sel = 3'b001;
        4'b1111:                            exp_hsize_from_sel = 3'b010;
        default:                            exp_hsize_from_sel = 3'b111; // invalid
      endcase
    end
  endfunction

  // AHB Slave BFM & Protocol Checker
  always @(posedge hclk) begin
    if (!hreset_n || !rst_i) begin
      hready            <= 1'b1;
      hresp             <= 2'b00;
      hrdata            <= 32'h0000_0000;
      dp_active         <= 1'b0;
      dp_addr           <= 32'h0000_0000;
      dp_size           <= 3'b000;
      dp_write          <= 1'b0;
      wait_cnt          <= 0;
      prev_stalled_ap   <= 1'b0;
      check_hwdata_hold <= 1'b0;
    end else begin
      hresp <= 2'b00;

      // 1. Check AHB Protocol Rules
      if (htrans === 2'b11) begin
        $display("FAIL: [%0t] htrans == SEQ (2'b11) observed, only SINGLE transfers allowed", $time);
        errors = errors + 1;
      end

      if ((htrans == 2'b10) && (hburst !== 3'b000)) begin
        $display("FAIL: [%0t] hburst expected 3'b000 (SINGLE), got %b", $time, hburst);
        errors = errors + 1;
      end

      // Check address phase holding during hready == 0
      if (prev_stalled_ap) begin
        if (htrans !== 2'b10) begin
          $display("FAIL: [%0t] htrans changed from NONSEQ while hready was 0 (got %b)", $time, htrans);
          errors = errors + 1;
        end
        if (haddr !== held_haddr) begin
          $display("FAIL: [%0t] haddr changed while hready was 0: expected %h, got %h", $time, held_haddr, haddr);
          errors = errors + 1;
        end
        if (hsize !== held_hsize) begin
          $display("FAIL: [%0t] hsize changed while hready was 0: expected %b, got %b", $time, held_hsize, hsize);
          errors = errors + 1;
        end
        if (hwrite !== held_hwrite) begin
          $display("FAIL: [%0t] hwrite changed while hready was 0: expected %b, got %b", $time, held_hwrite, hwrite);
          errors = errors + 1;
        end
        if (hburst !== held_hburst) begin
          $display("FAIL: [%0t] hburst changed while hready was 0: expected %b, got %b", $time, held_hburst, hburst);
          errors = errors + 1;
        end
      end

      if ((htrans == 2'b10) && !hready) begin
        prev_stalled_ap <= 1'b1;
        held_haddr      <= haddr;
        held_hsize      <= hsize;
        held_hwrite     <= hwrite;
        held_hburst     <= hburst;
      end else begin
        prev_stalled_ap <= 1'b0;
      end

      // Check hwdata holding during stalled write data phase
      if (check_hwdata_hold) begin
        if (hwdata !== held_hwdata) begin
          $display("FAIL: [%0t] hwdata changed while hready was 0: expected %h, got %h", $time, held_hwdata, hwdata);
          errors = errors + 1;
        end
      end

      // Check ack_o not asserted while AHB slave is busy (hready == 0) in data phase
      if (dp_active && !hready && ack_o) begin
        $display("FAIL: [%0t] ack_o asserted prematurely while AHB hready == 0", $time);
        errors = errors + 1;
      end

      // Check address alignment & expected attributes on valid NONSEQ
      if (htrans == 2'b10) begin
        ahb_seen_nonseq <= 1'b1;
        if (hsize == 3'b010 && haddr[1:0] != 2'b00) begin
          $display("FAIL: [%0t] Unaligned word haddr %h for hsize=010", $time, haddr);
          errors = errors + 1;
        end
        if (hsize == 3'b001 && haddr[0] != 1'b0) begin
          $display("FAIL: [%0t] Unaligned halfword haddr %h for hsize=001", $time, haddr);
          errors = errors + 1;
        end
        if (expect_valid_tx) begin
          if (haddr[31:2] !== active_wb_addr[31:2]) begin
            $display("FAIL: [%0t] haddr[31:2] mismatch: expected %h, got %h", $time, active_wb_addr[31:2], haddr[31:2]);
            errors = errors + 1;
          end
          if (exp_hsize_from_sel(active_sel) != 3'b111 && hsize !== exp_hsize_from_sel(active_sel)) begin
            $display("FAIL: [%0t] hsize mismatch for sel_i=%b: expected %b, got %b", $time, active_sel, exp_hsize_from_sel(active_sel), hsize);
            errors = errors + 1;
          end
        end
      end

      // 2. AHB Slave Data Phase & Address Phase Handling
      if (hready) begin
        check_hwdata_hold <= 1'b0;

        // Complete active data phase
        if (dp_active && dp_write) begin
          // Calibrate endianness on first known word write of 32'h11223344
          if (!endian_calibrated && dp_size == 3'b010) begin
            if (hwdata == 32'h1122_3344) begin
              byte_swap = 1'b0;
              endian_calibrated = 1'b1;
            end else if (hwdata == 32'h4433_2211) begin
              byte_swap = 1'b1;
              endian_calibrated = 1'b1;
            end else begin
              $display("FAIL: [%0t] Calibration word write hwdata mismatch: expected 11223344 or 44332211, got %h", $time, hwdata);
              errors = errors + 1;
              byte_swap = 1'b0;
              endian_calibrated = 1'b1;
            end
          end

          case (dp_size)
            3'b010: begin // Word
              slave_mem[dp_addr[9:2]] <= hwdata;
            end
            3'b001: begin // Halfword
              if (!byte_swap || !be_addr_inv) begin
                if (dp_addr[1] == 1'b0)
                  slave_mem[dp_addr[9:2]][15:0]  <= hwdata[15:0];
                else
                  slave_mem[dp_addr[9:2]][31:16] <= hwdata[31:16];
              end else begin
                if (dp_addr[1] == 1'b0)
                  slave_mem[dp_addr[9:2]][31:16] <= hwdata[31:16];
                else
                  slave_mem[dp_addr[9:2]][15:0]  <= hwdata[15:0];
              end
            end
            3'b000: begin // Byte
              if (!byte_swap || !be_addr_inv) begin
                case (dp_addr[1:0])
                  2'b00: slave_mem[dp_addr[9:2]][7:0]   <= hwdata[7:0];
                  2'b01: slave_mem[dp_addr[9:2]][15:8]  <= hwdata[15:8];
                  2'b10: slave_mem[dp_addr[9:2]][23:16] <= hwdata[23:16];
                  2'b11: slave_mem[dp_addr[9:2]][31:24] <= hwdata[31:24];
                endcase
              end else begin
                case (dp_addr[1:0])
                  2'b00: slave_mem[dp_addr[9:2]][31:24] <= hwdata[31:24];
                  2'b01: slave_mem[dp_addr[9:2]][23:16] <= hwdata[23:16];
                  2'b10: slave_mem[dp_addr[9:2]][15:8]  <= hwdata[15:8];
                  2'b11: slave_mem[dp_addr[9:2]][7:0]   <= hwdata[7:0];
                endcase
              end
            end
            default: ;
          endcase
        end

        // Sample next address phase
        if (htrans == 2'b10) begin
          // Calibrate BE addressing convention on first sel_i=4'b0001 transaction
          if (endian_calibrated && !be_addr_calibrated && expect_valid_tx && active_sel == 4'b0001) begin
            if (!byte_swap) begin
              if (haddr[1:0] !== 2'b00) begin
                $display("FAIL: [%0t] LE bridge expected haddr[1:0]==2'b00 for sel_i=4'b0001, got %b", $time, haddr[1:0]);
                errors = errors + 1;
              end
              be_addr_inv = 1'b0;
            end else begin
              if (haddr[1:0] == 2'b00)
                be_addr_inv = 1'b1; // BE-32
              else if (haddr[1:0] == 2'b11)
                be_addr_inv = 1'b0; // BE-8
              else begin
                $display("FAIL: [%0t] Unexpected haddr[1:0]=%b for sel_i=4'b0001", $time, haddr[1:0]);
                errors = errors + 1;
                be_addr_inv = 1'b1;
              end
            end
            be_addr_calibrated = 1'b1;
          end

          dp_active <= 1'b1;
          dp_addr   <= haddr;
          dp_size   <= hsize;
          dp_write  <= hwrite;

          if (slave_wait_cycles > 0) begin
            wait_cnt <= slave_wait_cycles;
            hready   <= 1'b0;
            hrdata   <= 32'hBAD0_BAD0;
          end else begin
            wait_cnt <= 0;
            hready   <= force_addr_stall ? 1'b0 : 1'b1;
            if (!hwrite)
              hrdata <= slave_mem[haddr[9:2]];
          end
        end else begin
          dp_active <= 1'b0;
          wait_cnt  <= 0;
          hready    <= force_addr_stall ? 1'b0 : 1'b1;
          hrdata    <= 32'h0000_0000;
        end
      end else begin
        // hready == 0: hold/stall
        if (dp_active && dp_write) begin
          check_hwdata_hold <= 1'b1;
          held_hwdata       <= hwdata;
        end

        if (wait_cnt > 1) begin
          wait_cnt <= wait_cnt - 1;
          hready   <= 1'b0;
          hrdata   <= 32'hBAD0_BAD0;
        end else if (wait_cnt == 1) begin
          wait_cnt <= 0;
          hready   <= force_addr_stall ? 1'b0 : 1'b1;
          if (dp_active && !dp_write)
            hrdata <= slave_mem[dp_addr[9:2]];
        end else begin
          // wait_cnt == 0 (address-phase forced stall)
          hready <= force_addr_stall ? 1'b0 : 1'b1;
          if (!force_addr_stall && dp_active && !dp_write)
            hrdata <= slave_mem[dp_addr[9:2]];
        end
      end
    end
  end

  // Task: Reset DUT
  task apply_reset;
    input rst_wb;
    input rst_ahb;
    input integer cycles;
    begin
      rst_i    <= rst_wb;
      hreset_n <= rst_ahb;
      cyc_i    <= 1'b0;
      stb_i    <= 1'b0;
      sel_i    <= 4'b0000;
      we_i     <= 1'b0;
      addr_i   <= 32'h0000_0000;
      data_i   <= 32'h0000_0000;
      expect_valid_tx <= 1'b0;
      repeat (cycles) @(posedge clk_i);
      // Check reset outputs
      if (ack_o !== 1'b0) begin
        $display("FAIL: [%0t] During reset (rst_i=%b, hreset_n=%b), ack_o expected 0, got %b", $time, rst_wb, rst_ahb, ack_o);
        errors = errors + 1;
      end
      if (htrans !== 2'b00) begin
        $display("FAIL: [%0t] During reset (rst_i=%b, hreset_n=%b), htrans expected 2'b00 (IDLE), got %b", $time, rst_wb, rst_ahb, htrans);
        errors = errors + 1;
      end
      if (hburst !== 3'b000) begin
        $display("FAIL: [%0t] During reset (rst_i=%b, hreset_n=%b), hburst expected 3'b000 (SINGLE), got %b", $time, rst_wb, rst_ahb, hburst);
        errors = errors + 1;
      end
      rst_i    <= 1'b1;
      hreset_n <= 1'b1;
      repeat (2) @(posedge clk_i);
    end
  endtask

  // Task: Single Wishbone Transaction (returns data_o for reads)
  task wb_tx;
    input         is_write;
    input  [3:0]  sel;
    input  [31:0] addr;
    input  [31:0] wdata;
    output [31:0] rdata;
    input         release_bus;
    integer       timeout;
    begin
      expect_valid_tx <= 1'b1;
      active_sel      <= sel;
      active_wb_addr  <= addr;
      ahb_seen_nonseq <= 1'b0;

      cyc_i  <= 1'b1;
      stb_i  <= 1'b1;
      we_i   <= is_write;
      sel_i  <= sel;
      addr_i <= addr;
      data_i <= wdata;

      timeout = 0;
      @(posedge clk_i);
      while (!ack_o && timeout < 100) begin
        @(posedge clk_i);
        timeout = timeout + 1;
      end

      if (!ack_o) begin
        $display("FAIL: [%0t] Timeout waiting for ack_o (we=%b, sel=%b, addr=%h)", $time, is_write, sel, addr);
        errors = errors + 1;
        rdata = 32'hXXXX_XXXX;
      end else begin
        rdata = data_o;
        if (!ahb_seen_nonseq && htrans !== 2'b10) begin
          $display("FAIL: [%0t] ack_o asserted without observing AHB NONSEQ transfer", $time);
          errors = errors + 1;
        end
      end

      if (release_bus) begin
        cyc_i <= 1'b0;
        stb_i <= 1'b0;
        we_i  <= 1'b0;
        expect_valid_tx <= 1'b0;
        @(posedge clk_i);
        if (ack_o !== 1'b0) begin
          $display("FAIL: [%0t] ack_o remained high after cyc_i/stb_i deasserted", $time);
          errors = errors + 1;
        end
      end
    end
  endtask

  // Helper task: Write and verify readback
  task wb_write;
    input [3:0]  sel;
    input [31:0] addr;
    input [31:0] wdata;
    reg   [31:0] dummy;
    begin
      wb_tx(1'b1, sel, addr, wdata, dummy, 1'b1);
    end
  endtask

  task wb_read_check;
    input [3:0]  sel;
    input [31:0] addr;
    input [31:0] exp_data;
    reg   [31:0] got_data;
    begin
      wb_tx(1'b0, sel, addr, 32'h0, got_data, 1'b1);
      case (sel)
        4'b1111: begin
          if (got_data !== exp_data) begin
            $display("FAIL: [%0t] Word read mismatch at %h: expected %h, got %h", $time, addr, exp_data, got_data);
            errors = errors + 1;
          end
        end
        4'b0011: begin
          if (got_data[15:0] !== exp_data[15:0]) begin
            $display("FAIL: [%0t] Low halfword read mismatch at %h: expected %h, got %h", $time, addr, exp_data[15:0], got_data[15:0]);
            errors = errors + 1;
          end
        end
        4'b1100: begin
          if (got_data[31:16] !== exp_data[31:16]) begin
            $display("FAIL: [%0t] High halfword read mismatch at %h: expected %h, got %h", $time, addr, exp_data[31:16], got_data[31:16]);
            errors = errors + 1;
          end
        end
        4'b0001: begin
          if (got_data[7:0] !== exp_data[7:0]) begin
            $display("FAIL: [%0t] Byte0 read mismatch at %h: expected %h, got %h", $time, addr, exp_data[7:0], got_data[7:0]);
            errors = errors + 1;
          end
        end
        4'b0010: begin
          if (got_data[15:8] !== exp_data[15:8]) begin
            $display("FAIL: [%0t] Byte1 read mismatch at %h: expected %h, got %h", $time, addr, exp_data[15:8], got_data[15:8]);
            errors = errors + 1;
          end
        end
        4'b0100: begin
          if (got_data[23:16] !== exp_data[23:16]) begin
            $display("FAIL: [%0t] Byte2 read mismatch at %h: expected %h, got %h", $time, addr, exp_data[23:16], got_data[23:16]);
            errors = errors + 1;
          end
        end
        4'b1000: begin
          if (got_data[31:24] !== exp_data[31:24]) begin
            $display("FAIL: [%0t] Byte3 read mismatch at %h: expected %h, got %h", $time, addr, exp_data[31:24], got_data[31:24]);
            errors = errors + 1;
          end
        end
        default: ;
      endcase
    end
  endtask

  // Task: Invalid sel_i transaction (bounded wait, no error on missing ack)
  task wb_invalid_sel_tx;
    input [3:0]  sel;
    input [31:0] addr;
    input [31:0] wdata;
    integer timeout;
    begin
      expect_valid_tx <= 1'b0;
      cyc_i  <= 1'b1;
      stb_i  <= 1'b1;
      we_i   <= 1'b1;
      sel_i  <= sel;
      addr_i <= addr;
      data_i <= wdata;
      timeout = 0;
      @(posedge clk_i);
      while (!ack_o && timeout < 15) begin
        if (ack_o === 1'bx || htrans === 2'bxx) begin
          $display("FAIL: [%0t] X/Z observed during invalid sel_i=%b", $time, sel);
          errors = errors + 1;
        end
        @(posedge clk_i);
        timeout = timeout + 1;
      end
      cyc_i <= 1'b0;
      stb_i <= 1'b0;
      we_i  <= 1'b0;
      repeat (3) @(posedge clk_i);
    end
  endtask

  reg [31:0] rdata_tmp;

  // Main Test Sequence
  initial begin
    // Initialize signals and memory
    rst_i              = 1'b0;
    hreset_n           = 1'b0;
    cyc_i              = 1'b0;
    stb_i              = 1'b0;
    sel_i              = 4'b0000;
    we_i               = 1'b0;
    addr_i             = 32'h0000_0000;
    data_i             = 32'h0000_0000;
    slave_wait_cycles  = 0;
    force_addr_stall   = 1'b0;
    endian_calibrated  = 1'b0;
    byte_swap          = 1'b0;
    be_addr_calibrated = 1'b0;
    be_addr_inv        = 1'b0;
    expect_valid_tx    = 1'b0;
    active_sel         = 4'b0000;
    active_wb_addr     = 32'h0000_0000;
    ahb_seen_nonseq    = 1'b0;

    for (i = 0; i < 256; i = i + 1) begin
      slave_mem[i] = 32'h0000_0000;
    end

    // ---------------------------------------------------------
    // Test 1: Reset Behavior (both resets, rst_i only, hreset_n only)
    // ---------------------------------------------------------
    $display("INFO: Running Test 1 - Reset Behavior");
    apply_reset(1'b0, 1'b0, 4);

    // Check idle state after reset
    if (ack_o !== 1'b0 || htrans !== 2'b00) begin
      $display("FAIL: [%0t] Idle outputs invalid after reset: ack_o=%b, htrans=%b", $time, ack_o, htrans);
      errors = errors + 1;
    end

    // Test rst_i only while active
    apply_reset(1'b0, 1'b1, 3);
    // Test hreset_n only while active
    apply_reset(1'b1, 1'b0, 3);

    // ---------------------------------------------------------
    // Test 2: Basic Word Write & Read + Endianness Calibration
    // ---------------------------------------------------------
    $display("INFO: Running Test 2 - Basic Word Write & Read");
    wb_write(4'b1111, 32'h0000_0000, 32'h1122_3344);
    wb_read_check(4'b1111, 32'h0000_0000, 32'h1122_3344);

    wb_write(4'b1111, 32'h0000_0004, 32'hDEAD_BEEF);
    wb_write(4'b1111, 32'h0000_0008, 32'h55AA_1234);
    wb_write(4'b1111, 32'h1000_01FC, 32'hA5A5_5A5A);
    wb_read_check(4'b1111, 32'h0000_0004, 32'hDEAD_BEEF);
    wb_read_check(4'b1111, 32'h0000_0008, 32'h55AA_1234);
    wb_read_check(4'b1111, 32'h1000_01FC, 32'hA5A5_5A5A);

    // ---------------------------------------------------------
    // Test 3: Address Fixing with Unaligned Wishbone Addresses
    // ---------------------------------------------------------
    $display("INFO: Running Test 3 - Address Fixing");
    wb_write(4'b1111, 32'h0000_0043, 32'hABCD_EF01);
    wb_read_check(4'b1111, 32'h0000_0040, 32'hABCD_EF01);
    wb_read_check(4'b1111, 32'h0000_0042, 32'hABCD_EF01);

    // ---------------------------------------------------------
    // Test 4: Byte-Level Transactions
    // ---------------------------------------------------------
    $display("INFO: Running Test 4 - Byte-Level Transactions");
    wb_write(4'b1111, 32'h0000_0010, 32'hA0B1_C2D3);

    wb_write(4'b0001, 32'h0000_0010, 32'h1234_56EF);
    wb_read_check(4'b1111, 32'h0000_0010, 32'hA0B1_C2EF);

    wb_write(4'b0010, 32'h0000_0010, 32'h1234_789A);
    wb_read_check(4'b1111, 32'h0000_0010, 32'hA0B1_78EF);

    wb_write(4'b0100, 32'h0000_0010, 32'h1256_9ABC);
    wb_read_check(4'b1111, 32'h0000_0010, 32'hA056_78EF);

    wb_write(4'b1000, 32'h0000_0010, 32'h34DE_F012);
    wb_read_check(4'b1111, 32'h0000_0010, 32'h3456_78EF);

    // Read individual bytes back
    wb_read_check(4'b0001, 32'h0000_0010, 32'h0000_00EF);
    wb_read_check(4'b0010, 32'h0000_0010, 32'h0000_7800);
    wb_read_check(4'b0100, 32'h0000_0010, 32'h0056_0000);
    wb_read_check(4'b1000, 32'h0000_0010, 32'h3400_0000);

    // ---------------------------------------------------------
    // Test 5: Halfword-Level Transactions
    // ---------------------------------------------------------
    $display("INFO: Running Test 5 - Halfword-Level Transactions");
    wb_write(4'b1111, 32'h0000_0020, 32'h1122_3344);

    wb_write(4'b0011, 32'h0000_0020, 32'h9988_AABB);
    wb_read_check(4'b1111, 32'h0000_0020, 32'h1122_AABB);

    wb_write(4'b1100, 32'h0000_0021, 32'hCCDD_7766);
    wb_read_check(4'b1111, 32'h0000_0020, 32'hCCDD_AABB);

    wb_read_check(4'b0011, 32'h0000_0020, 32'h0000_AABB);
    wb_read_check(4'b1100, 32'h0000_0020, 32'hCCDD_0000);

    // ---------------------------------------------------------
    // Test 6: AHB Slave Busy / Wait States
    // ---------------------------------------------------------
    $display("INFO: Running Test 6 - AHB Slave Busy / Wait States");
    slave_wait_cycles = 3;
    wb_write(4'b1111, 32'h0000_0030, 32'hFACE_B00C);
    wb_read_check(4'b1111, 32'h0000_0030, 32'hFACE_B00C);

    slave_wait_cycles = 5;
    wb_write(4'b0010, 32'h0000_0030, 32'h0000_9900);
    wb_read_check(4'b1111, 32'h0000_0030, 32'hFACE_990C);
    slave_wait_cycles = 0;

    // Address phase stall (hready forced low before address accepted)
    force_addr_stall = 1'b1;
    @(posedge clk_i);
    expect_valid_tx <= 1'b1;
    active_sel      <= 4'b1111;
    active_wb_addr  <= 32'h0000_0034;
    ahb_seen_nonseq <= 1'b0;
    cyc_i  <= 1'b1;
    stb_i  <= 1'b1;
    we_i   <= 1'b1;
    sel_i  <= 4'b1111;
    addr_i <= 32'h0000_0034;
    data_i <= 32'h7788_99AA;

    repeat (3) @(posedge clk_i);
    force_addr_stall <= 1'b0;

    i = 0;
    while (!ack_o && i < 100) begin
      @(posedge clk_i);
      i = i + 1;
    end
    if (!ack_o) begin
      $display("FAIL: [%0t] Timeout after address-phase stall", $time);
      errors = errors + 1;
    end
    cyc_i <= 1'b0;
    stb_i <= 1'b0;
    we_i  <= 1'b0;
    expect_valid_tx <= 1'b0;
    @(posedge clk_i);
    wb_read_check(4'b1111, 32'h0000_0034, 32'h7788_99AA);

    // ---------------------------------------------------------
    // Test 7: Back-to-Back Transactions (0 and 2 wait states)
    // ---------------------------------------------------------
    $display("INFO: Running Test 7 - Back-to-Back Transactions");
    slave_wait_cycles = 0;
    wb_tx(1'b1, 4'b1111, 32'h0000_0050, 32'h0102_0304, rdata_tmp, 1'b0);
    wb_tx(1'b1, 4'b1111, 32'h0000_0054, 32'h0506_0708, rdata_tmp, 1'b0);
    wb_tx(1'b0, 4'b1111, 32'h0000_0050, 32'h0000_0000, rdata_tmp, 1'b0);
    if (rdata_tmp !== 32'h0102_0304) begin
      $display("FAIL: [%0t] B2B read1 mismatch: expected 01020304, got %h", $time, rdata_tmp);
      errors = errors + 1;
    end
    wb_tx(1'b0, 4'b1111, 32'h0000_0054, 32'h0000_0000, rdata_tmp, 1'b0);
    if (rdata_tmp !== 32'h0506_0708) begin
      $display("FAIL: [%0t] B2B read2 mismatch: expected 05060708, got %h", $time, rdata_tmp);
      errors = errors + 1;
    end
    wb_tx(1'b1, 4'b1111, 32'h0000_0050, 32'h9999_8888, rdata_tmp, 1'b0);
    wb_tx(1'b0, 4'b1111, 32'h0000_0050, 32'h0000_0000, rdata_tmp, 1'b1);
    if (rdata_tmp !== 32'h9999_8888) begin
      $display("FAIL: [%0t] B2B write-then-read same addr mismatch: expected 99998888, got %h", $time, rdata_tmp);
      errors = errors + 1;
    end

    // Back-to-back with wait states
    slave_wait_cycles = 2;
    wb_tx(1'b1, 4'b1111, 32'h0000_0060, 32'h1357_2468, rdata_tmp, 1'b0);
    wb_tx(1'b0, 4'b1111, 32'h0000_0060, 32'h0000_0000, rdata_tmp, 1'b1);
    if (rdata_tmp !== 32'h1357_2468) begin
      $display("FAIL: [%0t] B2B with wait states mismatch: expected 13572468, got %h", $time, rdata_tmp);
      errors = errors + 1;
    end
    slave_wait_cycles = 0;

    // cyc_i stays high, stb_i drops for 1 cycle between transactions
    wb_tx(1'b1, 4'b1111, 32'h0000_0064, 32'hAAAA_5555, rdata_tmp, 1'b0);
    stb_i <= 1'b0;
    expect_valid_tx <= 1'b0;
    @(posedge clk_i);
    wb_tx(1'b0, 4'b1111, 32'h0000_0064, 32'h0000_0000, rdata_tmp, 1'b1);
    if (rdata_tmp !== 32'hAAAA_5555) begin
      $display("FAIL: [%0t] cyc-held stb-toggled read mismatch: expected AAAA5555, got %h", $time, rdata_tmp);
      errors = errors + 1;
    end

    // ---------------------------------------------------------
    // Test 8: Invalid / Conflicting sel_i Values
    // ---------------------------------------------------------
    $display("INFO: Running Test 8 - Invalid Byte Selection");
    wb_write(4'b1111, 32'h0000_0080, 32'hCAFE_BABE);

    wb_invalid_sel_tx(4'b0000, 32'h0000_0080, 32'hDEAD_DEAD);
    wb_read_check(4'b1111, 32'h0000_0080, 32'hCAFE_BABE);

    wb_invalid_sel_tx(4'b0101, 32'h0000_0080, 32'hDEAD_DEAD);
    wb_invalid_sel_tx(4'b1010, 32'h0000_0080, 32'hDEAD_DEAD);
    wb_invalid_sel_tx(4'b0111, 32'h0000_0080, 32'hDEAD_DEAD);
    wb_invalid_sel_tx(4'b1110, 32'h0000_0080, 32'hDEAD_DEAD);

    // Ensure bridge recovers cleanly after invalid sel_i
    wb_write(4'b1111, 32'h0000_0084, 32'h55AA_F00F);
    wb_read_check(4'b1111, 32'h0000_0084, 32'h55AA_F00F);

    // ---------------------------------------------------------
    // Test 9: Partial Wishbone Idle (cyc without stb, stb without cyc)
    // ---------------------------------------------------------
    $display("INFO: Running Test 9 - Partial WB Idle");
    cyc_i <= 1'b1; stb_i <= 1'b0; we_i <= 1'b1; sel_i <= 4'b1111; addr_i <= 32'h0000_0090; data_i <= 32'h1234_1234;
    repeat (5) begin
      @(posedge clk_i);
      if (ack_o !== 1'b0 || htrans !== 2'b00) begin
        $display("FAIL: [%0t] Transaction started when stb_i==0 (ack_o=%b, htrans=%b)", $time, ack_o, htrans);
        errors = errors + 1;
      end
    end

    cyc_i <= 1'b0; stb_i <= 1'b1;
    repeat (5) begin
      @(posedge clk_i);
      if (ack_o !== 1'b0 || htrans !== 2'b00) begin
        $display("FAIL: [%0t] Transaction started when cyc_i==0 (ack_o=%b, htrans=%b)", $time, ack_o, htrans);
        errors = errors + 1;
      end
    end
    stb_i <= 1'b0;
    repeat (2) @(posedge clk_i);

    // ---------------------------------------------------------
    // Test 10: Mid-Transaction Reset Recovery
    // ---------------------------------------------------------
    $display("INFO: Running Test 10 - Mid-Transaction Reset Recovery");
    slave_wait_cycles = 4;
    cyc_i  <= 1'b1;
    stb_i  <= 1'b1;
    we_i   <= 1'b1;
    sel_i  <= 4'b1111;
    addr_i <= 32'h0000_00A0;
    data_i <= 32'hBEEF_CAFE;
    repeat (2) @(posedge clk_i);

    // Assert rst_i mid-flight
    apply_reset(1'b0, 1'b1, 3);
    slave_wait_cycles = 0;

    // Verify normal operation after mid-transaction reset
    wb_write(4'b1111, 32'h0000_00A4, 32'h0D0E_0A0D);
    wb_read_check(4'b1111, 32'h0000_00A4, 32'h0D0E_0A0D);

    // Final Summary
    if (errors == 0) begin
      $display("PASS");
    end else begin
      $display("FAIL: %0d errors", errors);
    end
    $finish;
  end

endmodule
