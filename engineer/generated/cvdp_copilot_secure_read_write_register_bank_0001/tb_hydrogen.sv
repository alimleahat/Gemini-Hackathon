`timescale 1ns/1ps

module tb;

  // =========================================================================
  // Default Parameter DUT Signals (8-bit addr, 8-bit data, 0xAB / 0xCD)
  // =========================================================================
  localparam DEF_ADDR_W = 8;
  localparam DEF_DATA_W = 8;
  localparam [DEF_DATA_W-1:0] DEF_CODE_0 = 8'hAB;
  localparam [DEF_DATA_W-1:0] DEF_CODE_1 = 8'hCD;

  reg  [DEF_ADDR_W-1:0] d_addr;
  reg  [DEF_DATA_W-1:0] d_data_in;
  reg                   d_rw_en;
  reg                   d_cap_pulse;
  reg                   d_rst_n;
  wire [DEF_DATA_W-1:0] d_data_out;

  secure_read_write_register_bank dut_default (
    .i_addr              (d_addr),
    .i_data_in           (d_data_in),
    .i_read_write_enable (d_rw_en),
    .i_capture_pulse     (d_cap_pulse),
    .i_rst_n             (d_rst_n),
    .o_data_out          (d_data_out)
  );

  // =========================================================================
  // Custom Parameter DUT Signals (4-bit addr, 16-bit data, 0xCAFE / 0xBEEF)
  // =========================================================================
  localparam CUST_ADDR_W = 4;
  localparam CUST_DATA_W = 16;
  localparam [CUST_DATA_W-1:0] CUST_CODE_0 = 16'hCAFE;
  localparam [CUST_DATA_W-1:0] CUST_CODE_1 = 16'hBEEF;

  reg  [CUST_ADDR_W-1:0] c_addr;
  reg  [CUST_DATA_W-1:0] c_data_in;
  reg                    c_rw_en;
  reg                    c_cap_pulse;
  reg                    c_rst_n;
  wire [CUST_DATA_W-1:0] c_data_out;

  secure_read_write_register_bank #(
    .p_address_width (CUST_ADDR_W),
    .p_data_width    (CUST_DATA_W),
    .p_unlock_code_0 (CUST_CODE_0),
    .p_unlock_code_1 (CUST_CODE_1)
  ) dut_custom (
    .i_addr              (c_addr),
    .i_data_in           (c_data_in),
    .i_read_write_enable (c_rw_en),
    .i_capture_pulse     (c_cap_pulse),
    .i_rst_n             (c_rst_n),
    .o_data_out          (c_data_out)
  );

  integer errors = 0;
  integer i;

  // =========================================================================
  // Helper Tasks for Default DUT
  // =========================================================================
  task def_reset;
    begin
      d_cap_pulse = 1'b0;
      d_rw_en     = 1'b0;
      d_addr      = {DEF_ADDR_W{1'b0}};
      d_data_in   = {DEF_DATA_W{1'b0}};
      d_rst_n     = 1'b0;
      #10;
      d_rst_n     = 1'b1;
      #10;
    end
  endtask

  task def_pulse;
    begin
      #5;
      d_cap_pulse = 1'b1;
      #5;
      d_cap_pulse = 1'b0;
      #5;
    end
  endtask

  task def_write;
    input [DEF_ADDR_W-1:0] addr;
    input [DEF_DATA_W-1:0] data;
    begin
      d_rw_en   = 1'b0;
      d_addr    = addr;
      d_data_in = data;
      #5;
      d_cap_pulse = 1'b1;
      #5;
      if (d_data_out !== {DEF_DATA_W{1'b0}}) begin
        $display("FAIL: [def_write] addr=0x%0h data=0x%0h expected o_data_out=0x00, got=0x%0h",
                 addr, data, d_data_out);
        errors = errors + 1;
      end
      d_cap_pulse = 1'b0;
      #5;
    end
  endtask

  task def_read_check;
    input [DEF_ADDR_W-1:0] addr;
    input [DEF_DATA_W-1:0] expected;
    input [8*40-1:0]       msg;
    begin
      d_rw_en   = 1'b1;
      d_addr    = addr;
      d_data_in = {DEF_DATA_W{1'b0}};
      #5;
      d_cap_pulse = 1'b1;
      #5;
      if (d_data_out !== expected) begin
        $display("FAIL: [def_read %0s] addr=0x%0h expected=0x%0h, got=0x%0h",
                 msg, addr, expected, d_data_out);
        errors = errors + 1;
      end
      d_cap_pulse = 1'b0;
      #5;
    end
  endtask

  task def_unlock;
    begin
      def_write(8'h00, DEF_CODE_0);
      def_write(8'h01, DEF_CODE_1);
    end
  endtask

  // =========================================================================
  // Helper Tasks for Custom DUT
  // =========================================================================
  task cust_reset;
    begin
      c_cap_pulse = 1'b0;
      c_rw_en     = 1'b0;
      c_addr      = {CUST_ADDR_W{1'b0}};
      c_data_in   = {CUST_DATA_W{1'b0}};
      c_rst_n     = 1'b0;
      #10;
      c_rst_n     = 1'b1;
      #10;
    end
  endtask

  task cust_write;
    input [CUST_ADDR_W-1:0] addr;
    input [CUST_DATA_W-1:0] data;
    begin
      c_rw_en   = 1'b0;
      c_addr    = addr;
      c_data_in = data;
      #5;
      c_cap_pulse = 1'b1;
      #5;
      if (c_data_out !== {CUST_DATA_W{1'b0}}) begin
        $display("FAIL: [cust_write] addr=0x%0h data=0x%0h expected o_data_out=0x0000, got=0x%0h",
                 addr, data, c_data_out);
        errors = errors + 1;
      end
      c_cap_pulse = 1'b0;
      #5;
    end
  endtask

  task cust_read_check;
    input [CUST_ADDR_W-1:0] addr;
    input [CUST_DATA_W-1:0] expected;
    input [8*40-1:0]        msg;
    begin
      c_rw_en   = 1'b1;
      c_addr    = addr;
      c_data_in = {CUST_DATA_W{1'b0}};
      #5;
      c_cap_pulse = 1'b1;
      #5;
      if (c_data_out !== expected) begin
        $display("FAIL: [cust_read %0s] addr=0x%0h expected=0x%0h, got=0x%0h",
                 msg, addr, expected, c_data_out);
        errors = errors + 1;
      end
      c_cap_pulse = 1'b0;
      #5;
    end
  endtask

  task cust_unlock;
    begin
      cust_write(4'h0, CUST_CODE_0);
      cust_write(4'h1, CUST_CODE_1);
    end
  endtask

  // =========================================================================
  // Main Test Sequence
  // =========================================================================
  initial begin
    // Initialize both DUTs
    def_reset();
    cust_reset();

    // -----------------------------------------------------------------------
    // Test 1: Locked state after reset - reads must return 0
    // -----------------------------------------------------------------------
    def_read_check(8'h00, 8'h00, "locked_init_0");
    def_read_check(8'h01, 8'h00, "locked_init_1");
    def_read_check(8'h02, 8'h00, "locked_init_2");
    def_read_check(8'hFF, 8'h00, "locked_init_FF");

    // -----------------------------------------------------------------------
    // Test 2: Invalid unlock sequences must keep bank locked
    // -----------------------------------------------------------------------
    // 2a. Wrong code at addr 0, right code at addr 1
    def_write(8'h00, 8'hAA);
    def_write(8'h01, DEF_CODE_1);
    def_read_check(8'h02, 8'h00, "bad_seq_wrong0");

    // 2b. Right code at addr 0, wrong code at addr 1
    def_write(8'h00, DEF_CODE_0);
    def_write(8'h01, 8'hCE);
    def_read_check(8'h02, 8'h00, "bad_seq_wrong1");

    // 2c. Reversed order: addr 1 first, then addr 0
    def_write(8'h01, DEF_CODE_1);
    def_write(8'h00, DEF_CODE_0);
    def_read_check(8'h02, 8'h00, "bad_seq_reversed");

    // Clean reset before valid unlock
    def_reset();

    // -----------------------------------------------------------------------
    // Test 3: Valid unlock, normal write/read, boundary addresses, data patterns
    // -----------------------------------------------------------------------
    def_unlock();

    // Write patterns across various addresses including boundaries (0x02, 0xFF)
    def_write(8'h02, 8'h55);
    def_write(8'h03, 8'hAA);
    def_write(8'h04, 8'h00);
    def_write(8'h05, 8'hFF);
    def_write(8'h7F, 8'h3C);
    def_write(8'h80, 8'hC3);
    def_write(8'hFE, 8'h12);
    def_write(8'hFF, 8'h9E);

    // Read back and verify
    def_read_check(8'h02, 8'h55, "unlocked_rd_02");
    def_read_check(8'h03, 8'hAA, "unlocked_rd_03");
    def_read_check(8'h04, 8'h00, "unlocked_rd_04");
    def_read_check(8'h05, 8'hFF, "unlocked_rd_05");
    def_read_check(8'h7F, 8'h3C, "unlocked_rd_7F");
    def_read_check(8'h80, 8'hC3, "unlocked_rd_80");
    def_read_check(8'hFE, 8'h12, "unlocked_rd_FE");
    def_read_check(8'hFF, 8'h9E, "unlocked_rd_FF");

    // Overwrite test
    def_write(8'h02, 8'h77);
    def_read_check(8'h02, 8'h77, "overwrite_rd_02");

    // -----------------------------------------------------------------------
    // Test 4: Addresses 0 and 1 are write-only even when unlocked
    // -----------------------------------------------------------------------
    def_read_check(8'h00, 8'h00, "unlocked_wo_00");
    def_read_check(8'h01, 8'h00, "unlocked_wo_01");

    // Verify bank is still unlocked after attempting to read 0 and 1
    def_read_check(8'h02, 8'h77, "still_unlocked_02");

    // -----------------------------------------------------------------------
    // Test 5: Re-locking via incorrect write to address 0 or 1 while unlocked
    // -----------------------------------------------------------------------
    // 5a. Wrong write to addr 0 should lock bank
    def_write(8'h00, 8'h00);
    def_read_check(8'h02, 8'h00, "relock_bad0_rd_02");

    // Attempted write while locked must NOT overwrite addr 2
    def_write(8'h02, 8'hEE);
    def_read_check(8'h02, 8'h00, "locked_wr_rd_02");

    // Re-unlock and verify old value 0x77 was preserved
    def_unlock();
    def_read_check(8'h02, 8'h77, "reunlock_preserv_02");

    // 5b. Wrong write to addr 1 should lock bank
    def_write(8'h01, 8'h00);
    def_read_check(8'hFF, 8'h00, "relock_bad1_rd_FF");

    // Attempted write while locked must NOT overwrite addr FF
    def_write(8'hFF, 8'h11);

    // Re-unlock and verify old value 0x9E was preserved
    def_unlock();
    def_read_check(8'hFF, 8'h9E, "reunlock_preserv_FF");

    // -----------------------------------------------------------------------
    // Test 6: Asynchronous active-low reset while unlocked resets unlock state
    // -----------------------------------------------------------------------
    def_write(8'h10, 8'h42);
    def_read_check(8'h10, 8'h42, "pre_async_rst");

    // Pulse i_rst_n asynchronously without capture pulse edge
    #3;
    d_rst_n = 1'b0;
    #4;
    d_rst_n = 1'b1;
    #3;

    // Must be locked now
    def_read_check(8'h10, 8'h00, "post_async_rst");
    def_write(8'h10, 8'h88);

    // Unlock and write/read to confirm recovery after async reset
    def_unlock();
    def_write(8'h10, 8'h5A);
    def_read_check(8'h10, 8'h5A, "recover_async_rst");

    // -----------------------------------------------------------------------
    // Test 7: Custom Parameterized Instance (4-bit addr, 16-bit data)
    // -----------------------------------------------------------------------
    // Locked after reset
    cust_read_check(4'h2, 16'h0000, "cust_locked_init");

    // Bad unlock (16-bit mismatch in upper byte)
    cust_write(4'h0, 16'hCAFF);
    cust_write(4'h1, CUST_CODE_1);
    cust_read_check(4'h2, 16'h0000, "cust_bad_unlock");

    // Valid unlock
    cust_unlock();

    // Write and read all accessible addresses 2..15
    for (i = 2; i < 16; i = i + 1) begin
      cust_write(i[CUST_ADDR_W-1:0], (16'h1000 + i[15:0] * 16'h0111));
    end

    // Addresses 0 and 1 must still read 0
    cust_read_check(4'h0, 16'h0000, "cust_wo_0");
    cust_read_check(4'h1, 16'h0000, "cust_wo_1");

    for (i = 2; i < 16; i = i + 1) begin
      cust_read_check(i[CUST_ADDR_W-1:0], (16'h1000 + i[15:0] * 16'h0111), "cust_rd_loop");
    end

    // Re-lock with wrong code on addr 0 and check write protection
    cust_write(4'h0, 16'hDEAD);
    cust_read_check(4'hF, 16'h0000, "cust_relocked_F");
    cust_write(4'hF, 16'h9999);

    cust_unlock();
    cust_read_check(4'hF, (16'h1000 + 15 * 16'h0111), "cust_preserv_F");

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    if (errors == 0) begin
      $display("PASS");
    end else begin
      $display("FAIL: %0d errors", errors);
    end
    $finish;
  end

endmodule
