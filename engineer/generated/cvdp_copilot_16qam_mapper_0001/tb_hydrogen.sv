`timescale 1ns/1ps

module tb;

  // -------------------------------------------------------------------------
  // DUT 1: Parameterized N = 2
  // -------------------------------------------------------------------------
  localparam N2 = 2;
  localparam IN_W = 4;
  localparam OUT_W = 3;

  reg  [N2*IN_W-1:0]           bits_n2;
  wire [(N2 + N2/2)*OUT_W-1:0] I_n2;
  wire [(N2 + N2/2)*OUT_W-1:0] Q_n2;

  qam16_mapper_interpolated #(
    .N(N2),
    .IN_WIDTH(IN_W),
    .OUT_WIDTH(OUT_W)
  ) dut_n2 (
    .bits(bits_n2),
    .I(I_n2),
    .Q(Q_n2)
  );

  // -------------------------------------------------------------------------
  // DUT 2: Default parameters (N = 4, IN_WIDTH = 4, OUT_WIDTH = 3)
  // -------------------------------------------------------------------------
  localparam N4 = 4;

  reg  [N4*IN_W-1:0]           bits_n4;
  wire [(N4 + N4/2)*OUT_W-1:0] I_n4;
  wire [(N4 + N4/2)*OUT_W-1:0] Q_n4;

  qam16_mapper_interpolated dut_n4 (
    .bits(bits_n4),
    .I(I_n4),
    .Q(Q_n4)
  );

  // -------------------------------------------------------------------------
  // DUT 3: Parameterized N = 6
  // -------------------------------------------------------------------------
  localparam N6 = 6;

  reg  [N6*IN_W-1:0]           bits_n6;
  wire [(N6 + N6/2)*OUT_W-1:0] I_n6;
  wire [(N6 + N6/2)*OUT_W-1:0] Q_n6;

  qam16_mapper_interpolated #(
    .N(N6),
    .IN_WIDTH(IN_W),
    .OUT_WIDTH(OUT_W)
  ) dut_n6 (
    .bits(bits_n6),
    .I(I_n6),
    .Q(Q_n6)
  );

  // -------------------------------------------------------------------------
  // Verification Infrastructure
  // -------------------------------------------------------------------------
  integer errors = 0;
  integer i, j;
  reg [31:0] lfsr;

  function signed [2:0] map_2bit;
    input [1:0] b;
    begin
      case (b)
        2'b00: map_2bit = 3'sb101; // -3
        2'b01: map_2bit = 3'sb111; // -1
        2'b10: map_2bit = 3'sb001; // +1
        2'b11: map_2bit = 3'sb011; // +3
      endcase
    end
  endfunction

  task check_sample;
    input integer n_syms;
    input integer out_idx;
    input [23:0] bits_vec;
    input signed [2:0] exp_val;
    input signed [2:0] got_val;
    input is_q;
    begin
      if (got_val !== exp_val) begin
        if (errors < 50) begin
          if (is_q)
            $display("FAIL: N=%0d bits=0x%0h Q[%0d] expected %0d (3'b%03b), got %0d (3'b%03b)",
                     n_syms, bits_vec, out_idx, exp_val, exp_val, got_val, got_val);
          else
            $display("FAIL: N=%0d bits=0x%0h I[%0d] expected %0d (3'b%03b), got %0d (3'b%03b)",
                     n_syms, bits_vec, out_idx, exp_val, exp_val, got_val, got_val);
        end
        errors = errors + 1;
      end
    end
  endtask

  task verify_dut;
    input integer n_syms;
    input [23:0] b_in;
    input [26:0] i_got;
    input [26:0] q_got;

    integer p;
    reg [3:0] sym0, sym1;
    reg signed [2:0] s0_i, s1_i, interp_i;
    reg signed [2:0] s0_q, s1_q, interp_q;
    reg signed [3:0] sum_i, sum_q;
    reg signed [2:0] got_i0, got_i1, got_i2;
    reg signed [2:0] got_q0, got_q1, got_q2;
    begin
      for (p = 0; p < n_syms / 2; p = p + 1) begin
        sym0 = b_in[(2*p)*4 +: 4];
        sym1 = b_in[(2*p + 1)*4 +: 4];

        s0_i = map_2bit(sym0[3:2]);
        s0_q = map_2bit(sym0[1:0]);
        s1_i = map_2bit(sym1[3:2]);
        s1_q = map_2bit(sym1[1:0]);

        sum_i = $signed({s0_i[2], s0_i}) + $signed({s1_i[2], s1_i});
        sum_q = $signed({s0_q[2], s0_q}) + $signed({s1_q[2], s1_q});
        interp_i = sum_i >>> 1;
        interp_q = sum_q >>> 1;

        got_i0 = i_got[(3*p + 0)*3 +: 3];
        got_i1 = i_got[(3*p + 1)*3 +: 3];
        got_i2 = i_got[(3*p + 2)*3 +: 3];

        got_q0 = q_got[(3*p + 0)*3 +: 3];
        got_q1 = q_got[(3*p + 1)*3 +: 3];
        got_q2 = q_got[(3*p + 2)*3 +: 3];

        check_sample(n_syms, 3*p + 0, b_in, s0_i,     got_i0, 1'b0);
        check_sample(n_syms, 3*p + 1, b_in, interp_i, got_i1, 1'b0);
        check_sample(n_syms, 3*p + 2, b_in, s1_i,     got_i2, 1'b0);

        check_sample(n_syms, 3*p + 0, b_in, s0_q,     got_q0, 1'b1);
        check_sample(n_syms, 3*p + 1, b_in, interp_q, got_q1, 1'b1);
        check_sample(n_syms, 3*p + 2, b_in, s1_q,     got_q2, 1'b1);
      end
    end
  endtask

  function [31:0] next_rand;
    input [31:0] state;
    begin
      next_rand = {state[30:0], state[31] ^ state[21] ^ state[1] ^ state[0]};
    end
  endfunction

  // -------------------------------------------------------------------------
  // Main Test Stimulus
  // -------------------------------------------------------------------------
  initial begin
    bits_n2 = 8'h00;
    bits_n4 = 16'h0000;
    bits_n6 = 24'h000000;
    lfsr    = 32'hACE1_2025;
    #1;

    // 1. Exhaustive test for N = 2 (all 256 possible 8-bit combinations)
    for (i = 0; i < 256; i = i + 1) begin
      bits_n2 = i[7:0];
      #1;
      verify_dut(N2, {16'h0000, bits_n2}, {18'h0, I_n2}, {18'h0, Q_n2});
    end

    // 2. Corner cases for N = 4 (default parameters)
    bits_n4 = 16'h0000; #1; verify_dut(N4, {8'h00, bits_n4}, {9'h0, I_n4}, {9'h0, Q_n4});
    bits_n4 = 16'hFFFF; #1; verify_dut(N4, {8'h00, bits_n4}, {9'h0, I_n4}, {9'h0, Q_n4});
    bits_n4 = 16'h5555; #1; verify_dut(N4, {8'h00, bits_n4}, {9'h0, I_n4}, {9'h0, Q_n4});
    bits_n4 = 16'hAAAA; #1; verify_dut(N4, {8'h00, bits_n4}, {9'h0, I_n4}, {9'h0, Q_n4});
    bits_n4 = 16'h0F0F; #1; verify_dut(N4, {8'h00, bits_n4}, {9'h0, I_n4}, {9'h0, Q_n4});
    bits_n4 = 16'hF0F0; #1; verify_dut(N4, {8'h00, bits_n4}, {9'h0, I_n4}, {9'h0, Q_n4});
    bits_n4 = 16'h3C3C; #1; verify_dut(N4, {8'h00, bits_n4}, {9'h0, I_n4}, {9'h0, Q_n4});
    bits_n4 = 16'hC3C3; #1; verify_dut(N4, {8'h00, bits_n4}, {9'h0, I_n4}, {9'h0, Q_n4});

    // Walking-1 and walking-0 across all 16 input bits for N = 4
    for (i = 0; i < 16; i = i + 1) begin
      bits_n4 = (16'h0001 << i);
      #1;
      verify_dut(N4, {8'h00, bits_n4}, {9'h0, I_n4}, {9'h0, Q_n4});

      bits_n4 = ~(16'h0001 << i);
      #1;
      verify_dut(N4, {8'h00, bits_n4}, {9'h0, I_n4}, {9'h0, Q_n4});
    end

    // Sweep all 256 pair combinations in pair 0 and pair 1 independently for N = 4
    for (i = 0; i < 256; i = i + 1) begin
      bits_n4 = {8'hA5, i[7:0]};
      #1;
      verify_dut(N4, {8'h00, bits_n4}, {9'h0, I_n4}, {9'h0, Q_n4});

      bits_n4 = {i[7:0], 8'h3E};
      #1;
      verify_dut(N4, {8'h00, bits_n4}, {9'h0, I_n4}, {9'h0, Q_n4});
    end

    // Pseudo-random vectors for N = 4
    for (i = 0; i < 500; i = i + 1) begin
      lfsr = next_rand(lfsr);
      bits_n4 = lfsr[15:0];
      #1;
      verify_dut(N4, {8'h00, bits_n4}, {9'h0, I_n4}, {9'h0, Q_n4});
    end

    // 3. Corner cases & pseudo-random vectors for N = 6
    bits_n6 = 24'h000000; #1; verify_dut(N6, bits_n6, I_n6, Q_n6);
    bits_n6 = 24'hFFFFFF; #1; verify_dut(N6, bits_n6, I_n6, Q_n6);
    bits_n6 = 24'h0F0F0F; #1; verify_dut(N6, bits_n6, I_n6, Q_n6);
    bits_n6 = 24'hF0F0F0; #1; verify_dut(N6, bits_n6, I_n6, Q_n6);
    bits_n6 = 24'h123456; #1; verify_dut(N6, bits_n6, I_n6, Q_n6);
    bits_n6 = 24'hFEDCBA; #1; verify_dut(N6, bits_n6, I_n6, Q_n6);

    for (i = 0; i < 24; i = i + 1) begin
      bits_n6 = (24'h000001 << i);
      #1;
      verify_dut(N6, bits_n6, I_n6, Q_n6);
    end

    for (i = 0; i < 300; i = i + 1) begin
      lfsr = next_rand(lfsr);
      bits_n6 = lfsr[23:0];
      #1;
      verify_dut(N6, bits_n6, I_n6, Q_n6);
    end

    // -----------------------------------------------------------------------
    // Final Summary
    // -----------------------------------------------------------------------
    if (errors == 0)
      $display("PASS");
    else
      $display("FAIL: %0d errors", errors);

    $finish;
  end

endmodule
