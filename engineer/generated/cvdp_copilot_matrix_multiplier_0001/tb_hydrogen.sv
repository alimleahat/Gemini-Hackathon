`timescale 1ns/1ps

module tb;
  integer errors = 0;
  integer seed = 32'hCAFE_BABE;
  integer r_idx, c_idx, t_idx;

  // -------------------------------------------------------------------------
  // DUT 1: Standard 4x4 * 4x4, 8-bit unsigned inputs, 18-bit unsigned outputs
  // -------------------------------------------------------------------------
  reg  [4*4*8-1:0]  a_4x4;
  reg  [4*4*8-1:0]  b_4x4;
  wire [4*4*18-1:0] c_4x4;

  matrix_multiplier #(
    .ROW_A(4),
    .COL_A(4),
    .ROW_B(4),
    .COL_B(4),
    .INPUT_DATA_WIDTH(8),
    .OUTPUT_DATA_WIDTH(18)
  ) dut_4x4 (
    .matrix_a(a_4x4),
    .matrix_b(b_4x4),
    .matrix_c(c_4x4)
  );

  // -------------------------------------------------------------------------
  // DUT 2: Non-square 2x3 * 3x2 (Spec Example), 8-bit inputs, 18-bit outputs
  // -------------------------------------------------------------------------
  reg  [2*3*8-1:0]  a_2x3;
  reg  [3*2*8-1:0]  b_2x3;
  wire [2*2*18-1:0] c_2x3;

  matrix_multiplier #(
    .ROW_A(2),
    .COL_A(3),
    .ROW_B(3),
    .COL_B(2),
    .INPUT_DATA_WIDTH(8),
    .OUTPUT_DATA_WIDTH(18)
  ) dut_2x3 (
    .matrix_a(a_2x3),
    .matrix_b(b_2x3),
    .matrix_c(c_2x3)
  );

  // -------------------------------------------------------------------------
  // DUT 3: Non-square 4x5 * 5x3, 4-bit inputs, 11-bit outputs
  // -------------------------------------------------------------------------
  reg  [4*5*4-1:0]  a_4x5;
  reg  [5*3*4-1:0]  b_4x5;
  wire [4*3*11-1:0] c_4x5;

  matrix_multiplier #(
    .ROW_A(4),
    .COL_A(5),
    .ROW_B(5),
    .COL_B(3),
    .INPUT_DATA_WIDTH(4),
    .OUTPUT_DATA_WIDTH(11)
  ) dut_4x5 (
    .matrix_a(a_4x5),
    .matrix_b(b_4x5),
    .matrix_c(c_4x5)
  );

  // -------------------------------------------------------------------------
  // DUT 4: Edge case 1x1 * 1x1, 8-bit inputs, 16-bit outputs
  // -------------------------------------------------------------------------
  reg  [1*1*8-1:0]  a_1x1;
  reg  [1*1*8-1:0]  b_1x1;
  wire [1*1*16-1:0] c_1x1;

  matrix_multiplier #(
    .ROW_A(1),
    .COL_A(1),
    .ROW_B(1),
    .COL_B(1),
    .INPUT_DATA_WIDTH(8),
    .OUTPUT_DATA_WIDTH(16)
  ) dut_1x1 (
    .matrix_a(a_1x1),
    .matrix_b(b_1x1),
    .matrix_c(c_1x1)
  );

  // -------------------------------------------------------------------------
  // DUT 5: Dot product 1x4 * 4x1, 16-bit inputs, 34-bit outputs (>32-bit)
  // -------------------------------------------------------------------------
  reg  [1*4*16-1:0] a_1x4;
  reg  [4*1*16-1:0] b_1x4;
  wire [1*1*34-1:0] c_1x4;

  matrix_multiplier #(
    .ROW_A(1),
    .COL_A(4),
    .ROW_B(4),
    .COL_B(1),
    .INPUT_DATA_WIDTH(16),
    .OUTPUT_DATA_WIDTH(34)
  ) dut_1x4 (
    .matrix_a(a_1x4),
    .matrix_b(b_1x4),
    .matrix_c(c_1x4)
  );

  // -------------------------------------------------------------------------
  // DUT 6: Outer product 3x1 * 1x4, 8-bit inputs, 16-bit outputs
  // -------------------------------------------------------------------------
  reg  [3*1*8-1:0]  a_3x1;
  reg  [1*4*8-1:0]  b_3x1;
  wire [3*4*16-1:0] c_3x1;

  matrix_multiplier #(
    .ROW_A(3),
    .COL_A(1),
    .ROW_B(1),
    .COL_B(4),
    .INPUT_DATA_WIDTH(8),
    .OUTPUT_DATA_WIDTH(16)
  ) dut_3x1 (
    .matrix_a(a_3x1),
    .matrix_b(b_3x1),
    .matrix_c(c_3x1)
  );

  // -------------------------------------------------------------------------
  // Golden reference checker task
  // -------------------------------------------------------------------------
  task check_mult;
    input integer row_a;
    input integer col_a;
    input integer col_b;
    input integer iw;
    input integer ow;
    input [511:0] mat_a;
    input [511:0] mat_b;
    input [511:0] mat_c;
    input [8*32-1:0] label;
    integer r, c, k;
    reg [63:0] exp_val;
    reg [63:0] got_val;
    reg [63:0] a_val;
    reg [63:0] b_val;
    reg [63:0] mask_in;
    reg [63:0] mask_out;
    begin
      mask_in  = (iw == 64) ? 64'hFFFF_FFFF_FFFF_FFFF : ((64'd1 << iw) - 64'd1);
      mask_out = (ow == 64) ? 64'hFFFF_FFFF_FFFF_FFFF : ((64'd1 << ow) - 64'd1);
      for (r = 0; r < row_a; r = r + 1) begin
        for (c = 0; c < col_b; c = c + 1) begin
          exp_val = 64'd0;
          for (k = 0; k < col_a; k = k + 1) begin
            a_val = (mat_a >> ((r * col_a + k) * iw)) & mask_in;
            b_val = (mat_b >> ((k * col_b + c) * iw)) & mask_in;
            exp_val = exp_val + (a_val * b_val);
          end
          exp_val = exp_val & mask_out;
          got_val = (mat_c >> ((r * col_b + c) * ow)) & mask_out;
          if (got_val !== exp_val) begin
            $display("FAIL: [%0s] C[%0d][%0d] mismatch: expected %0d (0x%0h), got %0d (0x%0h)",
                     label, r, c, exp_val, exp_val, got_val, got_val);
            errors = errors + 1;
          end
        end
      end
    end
  endtask

  initial begin
    // Initialize all inputs to 0
    a_4x4 = 0; b_4x4 = 0;
    a_2x3 = 0; b_2x3 = 0;
    a_4x5 = 0; b_4x5 = 0;
    a_1x1 = 0; b_1x1 = 0;
    a_1x4 = 0; b_1x4 = 0;
    a_3x1 = 0; b_3x1 = 0;
    #1;

    // =======================================================================
    // Test Suite 1: 4x4 * 4x4 (8-bit -> 18-bit)
    // =======================================================================
    // 1a. All zeros
    check_mult(4, 4, 4, 8, 18, a_4x4, b_4x4, c_4x4, "4x4_all_zero");

    // 1b. Zero * Non-zero and Non-zero * Zero
    for (r_idx = 0; r_idx < 4; r_idx = r_idx + 1) begin
      for (c_idx = 0; c_idx < 4; c_idx = c_idx + 1) begin
        b_4x4[(r_idx*4 + c_idx)*8 +: 8] = r_idx * 4 + c_idx + 1;
      end
    end
    #1;
    check_mult(4, 4, 4, 8, 18, a_4x4, b_4x4, c_4x4, "4x4_zero_x_B");

    a_4x4 = b_4x4;
    b_4x4 = 0;
    #1;
    check_mult(4, 4, 4, 8, 18, a_4x4, b_4x4, c_4x4, "4x4_A_x_zero");

    // 1c. Identity matrix multiplication (A * I = A, I * B = B)
    b_4x4 = 0;
    for (r_idx = 0; r_idx < 4; r_idx = r_idx + 1) begin
      b_4x4[(r_idx*4 + r_idx)*8 +: 8] = 8'd1;
    end
    #1;
    check_mult(4, 4, 4, 8, 18, a_4x4, b_4x4, c_4x4, "4x4_A_x_I");

    b_4x4 = a_4x4;
    a_4x4 = 0;
    for (r_idx = 0; r_idx < 4; r_idx = r_idx + 1) begin
      a_4x4[(r_idx*4 + r_idx)*8 +: 8] = 8'd1;
    end
    #1;
    check_mult(4, 4, 4, 8, 18, a_4x4, b_4x4, c_4x4, "4x4_I_x_B");

    // 1d. Distinct elements across rows/cols (catches transpose/flattening errors)
    for (r_idx = 0; r_idx < 4; r_idx = r_idx + 1) begin
      for (c_idx = 0; c_idx < 4; c_idx = c_idx + 1) begin
        a_4x4[(r_idx*4 + c_idx)*8 +: 8] = r_idx * 10 + c_idx + 1;
        b_4x4[(r_idx*4 + c_idx)*8 +: 8] = (r_idx + 1) * 3 + c_idx * 7;
      end
    end
    #1;
    check_mult(4, 4, 4, 8, 18, a_4x4, b_4x4, c_4x4, "4x4_distinct");

    // 1e. Combinational immediate update check (single element A change, then B change)
    a_4x4[2*4*8 + 1*8 +: 8] = 8'd99;
    #1;
    check_mult(4, 4, 4, 8, 18, a_4x4, b_4x4, c_4x4, "4x4_comb_upd_A");

    b_4x4[1*4*8 + 3*8 +: 8] = 8'd77;
    #1;
    check_mult(4, 4, 4, 8, 18, a_4x4, b_4x4, c_4x4, "4x4_comb_upd_B");

    // 1f. Max unsigned overflow / unsigned MSB check (all 8'hFF -> 260100, and 8'h80)
    a_4x4 = {16{8'hFF}};
    b_4x4 = {16{8'hFF}};
    #1;
    check_mult(4, 4, 4, 8, 18, a_4x4, b_4x4, c_4x4, "4x4_max_FF");

    a_4x4 = {16{8'h80}};
    b_4x4 = {16{8'h80}};
    #1;
    check_mult(4, 4, 4, 8, 18, a_4x4, b_4x4, c_4x4, "4x4_msb_80");

    // 1g. Random 4x4 tests
    for (t_idx = 0; t_idx < 50; t_idx = t_idx + 1) begin
      for (r_idx = 0; r_idx < 16; r_idx = r_idx + 1) begin
        a_4x4[r_idx*8 +: 8] = $random(seed) & 8'hFF;
        b_4x4[r_idx*8 +: 8] = $random(seed) & 8'hFF;
      end
      #1;
      check_mult(4, 4, 4, 8, 18, a_4x4, b_4x4, c_4x4, "4x4_rand");
    end

    // =======================================================================
    // Test Suite 2: Non-square 2x3 * 3x2 (Spec Example)
    // =======================================================================
    // 2a. Zeros
    check_mult(2, 3, 2, 8, 18, a_2x3, b_2x3, c_2x3, "2x3_zero");

    // 2b. Exact flattening spec example
    a_2x3 = {8'd6, 8'd5, 8'd4, 8'd3, 8'd2, 8'd1};
    b_2x3 = {8'd12, 8'd11, 8'd10, 8'd9, 8'd8, 8'd7};
    #1;
    check_mult(2, 3, 2, 8, 18, a_2x3, b_2x3, c_2x3, "2x3_spec_example");
    if (c_2x3 !== {18'd154, 18'd139, 18'd64, 18'd58}) begin
      $display("FAIL: [2x3_spec_exact] expected 0x%0h, got 0x%0h",
               {18'd154, 18'd139, 18'd64, 18'd58}, c_2x3);
      errors = errors + 1;
    end

    // 2c. Immediate combinational update on 2x3
    a_2x3[0*8 +: 8] = 8'd100;
    #1;
    check_mult(2, 3, 2, 8, 18, a_2x3, b_2x3, c_2x3, "2x3_comb_upd_A");

    // 2d. Max values (3 * 255 * 255 = 195075)
    a_2x3 = {6{8'hFF}};
    b_2x3 = {6{8'hFF}};
    #1;
    check_mult(2, 3, 2, 8, 18, a_2x3, b_2x3, c_2x3, "2x3_max_FF");

    // 2e. Random 2x3 tests
    for (t_idx = 0; t_idx < 30; t_idx = t_idx + 1) begin
      for (r_idx = 0; r_idx < 6; r_idx = r_idx + 1) begin
        a_2x3[r_idx*8 +: 8] = $random(seed) & 8'hFF;
        b_2x3[r_idx*8 +: 8] = $random(seed) & 8'hFF;
      end
      #1;
      check_mult(2, 3, 2, 8, 18, a_2x3, b_2x3, c_2x3, "2x3_rand");
    end

    // =======================================================================
    // Test Suite 3: Non-square 4x5 * 5x3 (4-bit -> 11-bit)
    // =======================================================================
    // 3a. Zeros
    check_mult(4, 5, 3, 4, 11, a_4x5, b_4x5, c_4x5, "4x5_zero");

    // 3b. Max 4-bit values (5 * 15 * 15 = 1125)
    a_4x5 = {20{4'hF}};
    b_4x5 = {15{4'hF}};
    #1;
    check_mult(4, 5, 3, 4, 11, a_4x5, b_4x5, c_4x5, "4x5_max_F");

    // 3c. Distinct asymmetric values
    for (r_idx = 0; r_idx < 20; r_idx = r_idx + 1) begin
      a_4x5[r_idx*4 +: 4] = (r_idx + 1) & 4'hF;
    end
    for (r_idx = 0; r_idx < 15; r_idx = r_idx + 1) begin
      b_4x5[r_idx*4 +: 4] = (15 - r_idx) & 4'hF;
    end
    #1;
    check_mult(4, 5, 3, 4, 11, a_4x5, b_4x5, c_4x5, "4x5_distinct");

    // 3d. Random 4x5 tests
    for (t_idx = 0; t_idx < 30; t_idx = t_idx + 1) begin
      for (r_idx = 0; r_idx < 20; r_idx = r_idx + 1) begin
        a_4x5[r_idx*4 +: 4] = $random(seed) & 4'hF;
      end
      for (r_idx = 0; r_idx < 15; r_idx = r_idx + 1) begin
        b_4x5[r_idx*4 +: 4] = $random(seed) & 4'hF;
      end
      #1;
      check_mult(4, 5, 3, 4, 11, a_4x5, b_4x5, c_4x5, "4x5_rand");
    end

    // =======================================================================
    // Test Suite 4: Edge case 1x1 * 1x1 (8-bit -> 16-bit)
    // =======================================================================
    check_mult(1, 1, 1, 8, 16, a_1x1, b_1x1, c_1x1, "1x1_zero");

    a_1x1 = 8'd0; b_1x1 = 8'd255; #1;
    check_mult(1, 1, 1, 8, 16, a_1x1, b_1x1, c_1x1, "1x1_0x255");

    a_1x1 = 8'd255; b_1x1 = 8'd0; #1;
    check_mult(1, 1, 1, 8, 16, a_1x1, b_1x1, c_1x1, "1x1_255x0");

    a_1x1 = 8'd255; b_1x1 = 8'd255; #1;
    check_mult(1, 1, 1, 8, 16, a_1x1, b_1x1, c_1x1, "1x1_max");

    a_1x1 = 8'd128; b_1x1 = 8'd128; #1;
    check_mult(1, 1, 1, 8, 16, a_1x1, b_1x1, c_1x1, "1x1_msb");

    for (t_idx = 0; t_idx < 20; t_idx = t_idx + 1) begin
      a_1x1 = $random(seed) & 8'hFF;
      b_1x1 = $random(seed) & 8'hFF;
      #1;
      check_mult(1, 1, 1, 8, 16, a_1x1, b_1x1, c_1x1, "1x1_rand");
    end

    // =======================================================================
    // Test Suite 5: Dot product 1x4 * 4x1 (16-bit -> 34-bit)
    // =======================================================================
    check_mult(1, 4, 1, 16, 34, a_1x4, b_1x4, c_1x4, "1x4_zero");

    a_1x4 = {4{16'hFFFF}};
    b_1x4 = {4{16'hFFFF}};
    #1;
    check_mult(1, 4, 1, 16, 34, a_1x4, b_1x4, c_1x4, "1x4_max_FFFF");

    a_1x4 = {16'h8000, 16'h0001, 16'h1234, 16'hABCD};
    b_1x4 = {16'h8000, 16'hFFFF, 16'h5678, 16'h0002};
    #1;
    check_mult(1, 4, 1, 16, 34, a_1x4, b_1x4, c_1x4, "1x4_directed");

    for (t_idx = 0; t_idx < 20; t_idx = t_idx + 1) begin
      for (r_idx = 0; r_idx < 4; r_idx = r_idx + 1) begin
        a_1x4[r_idx*16 +: 16] = $random(seed) & 16'hFFFF;
        b_1x4[r_idx*16 +: 16] = $random(seed) & 16'hFFFF;
      end
      #1;
      check_mult(1, 4, 1, 16, 34, a_1x4, b_1x4, c_1x4, "1x4_rand");
    end

    // =======================================================================
    // Test Suite 6: Outer product 3x1 * 1x4 (8-bit -> 16-bit)
    // =======================================================================
    check_mult(3, 1, 4, 8, 16, a_3x1, b_3x1, c_3x1, "3x1_zero");

    a_3x1 = {8'd255, 8'd128, 8'd1};
    b_3x1 = {8'd255, 8'd200, 8'd17, 8'd0};
    #1;
    check_mult(3, 1, 4, 8, 16, a_3x1, b_3x1, c_3x1, "3x1_directed");

    for (t_idx = 0; t_idx < 20; t_idx = t_idx + 1) begin
      for (r_idx = 0; r_idx < 3; r_idx = r_idx + 1) begin
        a_3x1[r_idx*8 +: 8] = $random(seed) & 8'hFF;
      end
      for (c_idx = 0; c_idx < 4; c_idx = c_idx + 1) begin
        b_3x1[c_idx*8 +: 8] = $random(seed) & 8'hFF;
      end
      #1;
      check_mult(3, 1, 4, 8, 16, a_3x1, b_3x1, c_3x1, "3x1_rand");
    end

    // =======================================================================
    // Summary
    // =======================================================================
    if (errors == 0) begin
      $display("PASS");
    end else begin
      $display("FAIL: %0d errors", errors);
    end
    $finish;
  end
endmodule
