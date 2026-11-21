`timescale 1ns/1ps

module tb;

  // =========================================================================
  // Clock and global error counter
  // =========================================================================
  reg clk;
  integer errors = 0;
  integer seed = 32'h1357_2468;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // =========================================================================
  // DUT 0: Default parameters (N = 8, WIDTH = 8)
  // =========================================================================
  reg         rst;
  reg         start;
  reg  [63:0] in_data;
  wire        done;
  wire [63:0] out_data;

  sorting_engine dut (
    .clk      (clk),
    .rst      (rst),
    .start    (start),
    .in_data  (in_data),
    .done     (done),
    .out_data (out_data)
  );

  // =========================================================================
  // DUT 1: Parameterized (N = 4, WIDTH = 16)
  // =========================================================================
  reg         rst_p1;
  reg         start_p1;
  reg  [63:0] in_data_p1;
  wire        done_p1;
  wire [63:0] out_data_p1;

  sorting_engine #(.N(4), .WIDTH(16)) dut_p1 (
    .clk      (clk),
    .rst      (rst_p1),
    .start    (start_p1),
    .in_data  (in_data_p1),
    .done     (done_p1),
    .out_data (out_data_p1)
  );

  // =========================================================================
  // DUT 2: Parameterized (N = 2, WIDTH = 4)
  // =========================================================================
  reg        rst_p2;
  reg        start_p2;
  reg  [7:0] in_data_p2;
  wire       done_p2;
  wire [7:0] out_data_p2;

  sorting_engine #(.N(2), .WIDTH(4)) dut_p2 (
    .clk      (clk),
    .rst      (rst_p2),
    .start    (start_p2),
    .in_data  (in_data_p2),
    .done     (done_p2),
    .out_data (out_data_p2)
  );

  // =========================================================================
  // DUT 3: Parameterized (N = 5, WIDTH = 1)
  // =========================================================================
  reg        rst_p3;
  reg        start_p3;
  reg  [4:0] in_data_p3;
  wire       done_p3;
  wire [4:0] out_data_p3;

  sorting_engine #(.N(5), .WIDTH(1)) dut_p3 (
    .clk      (clk),
    .rst      (rst_p3),
    .start    (start_p3),
    .in_data  (in_data_p3),
    .done     (done_p3),
    .out_data (out_data_p3)
  );

  // =========================================================================
  // Reference golden ascending unsigned sort (index 0 at LSB)
  // =========================================================================
  function [63:0] ref_sort;
    input [63:0] din;
    input integer n;
    input integer w;
    integer i, j;
    reg [63:0] tmp;
    reg [63:0] mask;
    reg [63:0] a, b;
    begin
      tmp  = din;
      mask = (64'd1 << w) - 64'd1;
      for (i = 0; i < n; i = i + 1) begin
        for (j = 0; j < n - 1; j = j + 1) begin
          a = (tmp >> (j * w)) & mask;
          b = (tmp >> ((j + 1) * w)) & mask;
          if (a > b) begin
            tmp = (tmp & ~(mask << (j * w))) | (b << (j * w));
            tmp = (tmp & ~(mask << ((j + 1) * w))) | (a << ((j + 1) * w));
          end
        end
      end
      ref_sort = tmp;
    end
  endfunction

  // =========================================================================
  // Task for Default DUT (N = 8, WIDTH = 8)
  // =========================================================================
  task run_dut0;
    input [63:0] vec;
    input        check_stable;
    input        corrupt_after_start;
    input        back_to_back;
    reg   [63:0] expected;
    reg   [63:0] prev_out;
    integer      lat;
    reg          got_done;
    begin
      expected = ref_sort(vec, 8, 8);
      prev_out = out_data;
      got_done = 1'b0;

      @(negedge clk);
      in_data = vec;
      start   = 1'b1;

      @(posedge clk);
      #1;
      if (done !== 1'b0) begin
        $display("FAIL: [N=8,W=8] done asserted prematurely on start posedge (expected 0, got %b)", done);
        errors = errors + 1;
      end
      if (check_stable && (out_data !== prev_out)) begin
        $display("FAIL: [N=8,W=8] out_data changed on start posedge (expected %h, got %h)", prev_out, out_data);
        errors = errors + 1;
      end

      @(negedge clk);
      start = 1'b0;
      if (corrupt_after_start)
        in_data = ~vec;

      for (lat = 1; lat <= 68; lat = lat + 1) begin
        @(posedge clk);
        #1;
        if (done === 1'b1) begin
          got_done = 1'b1;
          if (lat < 56 || lat > 59) begin
            $display("FAIL: [N=8,W=8] unexpected latency %0d cycles after start posedge (expected ~56..58 for N*(N-1)+2)", lat);
            errors = errors + 1;
          end
          if (out_data !== expected) begin
            $display("FAIL: [N=8,W=8] out_data mismatch for in=%h (expected %h, got %h)", vec, expected, out_data);
            errors = errors + 1;
          end
          lat = 100; // exit loop
        end else if (done === 1'b0) begin
          if (check_stable && (out_data !== prev_out)) begin
            $display("FAIL: [N=8,W=8] out_data changed before done at cycle %0d (expected %h, got %h)", lat, prev_out, out_data);
            errors = errors + 1;
          end
        end else begin
          $display("FAIL: [N=8,W=8] done became X/Z (%b) at cycle %0d", done, lat);
          errors = errors + 1;
          lat = 100;
        end
      end

      if (!got_done) begin
        $display("FAIL: [N=8,W=8] timeout waiting for done on in=%h (done=%b)", vec, done);
        errors = errors + 1;
      end else begin
        // Verify done is a 1-cycle pulse and out_data remains stable
        @(posedge clk);
        #1;
        if (done !== 1'b0) begin
          $display("FAIL: [N=8,W=8] done remained high >1 cycle (expected 0, got %b)", done);
          errors = errors + 1;
        end
        if (out_data !== expected) begin
          $display("FAIL: [N=8,W=8] out_data did not hold sorted value after done (expected %h, got %h)", expected, out_data);
          errors = errors + 1;
        end
      end

      if (!back_to_back) begin
        @(posedge clk);
        #1;
        if (done !== 1'b0) begin
          $display("FAIL: [N=8,W=8] spurious done while idle (expected 0, got %b)", done);
          errors = errors + 1;
        end
      end
    end
  endtask

  // =========================================================================
  // Task for DUT 1 (N = 4, WIDTH = 16)
  // =========================================================================
  task run_dut_p1;
    input [63:0] vec;
    input        check_stable;
    reg   [63:0] expected;
    reg   [63:0] prev_out;
    integer      lat;
    reg          got_done;
    begin
      expected = ref_sort(vec, 4, 16);
      prev_out = out_data_p1;
      got_done = 1'b0;

      @(negedge clk);
      in_data_p1 = vec;
      start_p1   = 1'b1;

      @(posedge clk);
      #1;
      if (done_p1 !== 1'b0) begin
        $display("FAIL: [N=4,W=16] done asserted prematurely on start posedge (expected 0, got %b)", done_p1);
        errors = errors + 1;
      end

      @(negedge clk);
      start_p1 = 1'b0;

      // N*(N-1) = 12, expected ~12..15
      for (lat = 1; lat <= 24; lat = lat + 1) begin
        @(posedge clk);
        #1;
        if (done_p1 === 1'b1) begin
          got_done = 1'b1;
          if (lat < 12 || lat > 15) begin
            $display("FAIL: [N=4,W=16] unexpected latency %0d cycles (expected ~12..14)", lat);
            errors = errors + 1;
          end
          if (out_data_p1 !== expected) begin
            $display("FAIL: [N=4,W=16] out_data mismatch for in=%h (expected %h, got %h)", vec, expected, out_data_p1);
            errors = errors + 1;
          end
          lat = 100;
        end else if (done_p1 === 1'b0) begin
          if (check_stable && (out_data_p1 !== prev_out)) begin
            $display("FAIL: [N=4,W=16] out_data changed before done (expected %h, got %h)", prev_out, out_data_p1);
            errors = errors + 1;
          end
        end else begin
          $display("FAIL: [N=4,W=16] done became X/Z (%b)", done_p1);
          errors = errors + 1;
          lat = 100;
        end
      end

      if (!got_done) begin
        $display("FAIL: [N=4,W=16] timeout waiting for done on in=%h", vec);
        errors = errors + 1;
      end else begin
        @(posedge clk);
        #1;
        if (done_p1 !== 1'b0) begin
          $display("FAIL: [N=4,W=16] done stayed high >1 cycle (expected 0, got %b)", done_p1);
          errors = errors + 1;
        end
      end
    end
  endtask

  // =========================================================================
  // Task for DUT 2 (N = 2, WIDTH = 4)
  // =========================================================================
  task run_dut_p2;
    input [7:0] vec;
    reg   [7:0] expected;
    integer     lat;
    reg         got_done;
    begin
      expected = ref_sort({56'd0, vec}, 2, 4);
      got_done = 1'b0;

      @(negedge clk);
      in_data_p2 = vec;
      start_p2   = 1'b1;

      @(posedge clk);
      #1;
      @(negedge clk);
      start_p2 = 1'b0;

      // N*(N-1) = 2
      for (lat = 1; lat <= 12; lat = lat + 1) begin
        @(posedge clk);
        #1;
        if (done_p2 === 1'b1) begin
          got_done = 1'b1;
          if (lat < 2 || lat > 5) begin
            $display("FAIL: [N=2,W=4] unexpected latency %0d cycles (expected ~2..4)", lat);
            errors = errors + 1;
          end
          if (out_data_p2 !== expected) begin
            $display("FAIL: [N=2,W=4] out_data mismatch for in=%h (expected %h, got %h)", vec, expected, out_data_p2);
            errors = errors + 1;
          end
          lat = 100;
        end else if (done_p2 !== 1'b0) begin
          $display("FAIL: [N=2,W=4] done became X/Z (%b)", done_p2);
          errors = errors + 1;
          lat = 100;
        end
      end

      if (!got_done) begin
        $display("FAIL: [N=2,W=4] timeout waiting for done on in=%h", vec);
        errors = errors + 1;
      end else begin
        @(posedge clk);
        #1;
        if (done_p2 !== 1'b0) begin
          $display("FAIL: [N=2,W=4] done stayed high >1 cycle (expected 0, got %b)", done_p2);
          errors = errors + 1;
        end
      end
    end
  endtask

  // =========================================================================
  // Task for DUT 3 (N = 5, WIDTH = 1)
  // =========================================================================
  task run_dut_p3;
    input [4:0] vec;
    reg   [4:0] expected;
    integer     lat;
    reg         got_done;
    begin
      expected = ref_sort({59'd0, vec}, 5, 1);
      got_done = 1'b0;

      @(negedge clk);
      in_data_p3 = vec;
      start_p3   = 1'b1;

      @(posedge clk);
      #1;
      @(negedge clk);
      start_p3 = 1'b0;

      // N*(N-1) = 20
      for (lat = 1; lat <= 32; lat = lat + 1) begin
        @(posedge clk);
        #1;
        if (done_p3 === 1'b1) begin
          got_done = 1'b1;
          if (lat < 20 || lat > 23) begin
            $display("FAIL: [N=5,W=1] unexpected latency %0d cycles (expected ~20..22)", lat);
            errors = errors + 1;
          end
          if (out_data_p3 !== expected) begin
            $display("FAIL: [N=5,W=1] out_data mismatch for in=%b (expected %b, got %b)", vec, expected, out_data_p3);
            errors = errors + 1;
          end
          lat = 100;
        end else if (done_p3 !== 1'b0) begin
          $display("FAIL: [N=5,W=1] done became X/Z (%b)", done_p3);
          errors = errors + 1;
          lat = 100;
        end
      end

      if (!got_done) begin
        $display("FAIL: [N=5,W=1] timeout waiting for done on in=%b", vec);
        errors = errors + 1;
      end else begin
        @(posedge clk);
        #1;
        if (done_p3 !== 1'b0) begin
          $display("FAIL: [N=5,W=1] done stayed high >1 cycle (expected 0, got %b)", done_p3);
          errors = errors + 1;
        end
      end
    end
  endtask

  // =========================================================================
  // Main Test Sequence
  // =========================================================================
  integer k;
  reg [63:0] rand_vec;
  reg [63:0] saved_out;
  integer    wait_cyc;
  reg        saw_done_mid_rst;

  initial begin
    // Initialize all inputs
    rst        = 1'b1;
    start      = 1'b0;
    in_data    = 64'd0;
    rst_p1     = 1'b1;
    start_p1   = 1'b0;
    in_data_p1 = 64'd0;
    rst_p2     = 1'b1;
    start_p2   = 1'b0;
    in_data_p2 = 8'd0;
    rst_p3     = 1'b1;
    start_p3   = 1'b0;
    in_data_p3 = 5'd0;

    // -----------------------------------------------------------------------
    // Test 1: Asynchronous reset check before any clock edge & idle behavior
    // -----------------------------------------------------------------------
    #1;
    if (done !== 1'b0) begin
      $display("FAIL: [Reset] done not 0 under initial async reset (expected 0, got %b)", done);
      errors = errors + 1;
    end
    if (done_p1 !== 1'b0 || done_p2 !== 1'b0 || done_p3 !== 1'b0) begin
      $display("FAIL: [Reset] parameterized DUT done not 0 under async reset (got %b %b %b)", done_p1, done_p2, done_p3);
      errors = errors + 1;
    end

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    repeat (4) begin
      @(posedge clk);
      #1;
      if (done !== 1'b0) begin
        $display("FAIL: [Idle] done asserted without start (expected 0, got %b)", done);
        errors = errors + 1;
      end
    end

    // -----------------------------------------------------------------------
    // Test 2: Already sorted array (must NOT early-exit; checks fixed latency)
    // -----------------------------------------------------------------------
    run_dut0(64'h07_06_05_04_03_02_01_00, 1'b0, 1'b0, 1'b0);

    // -----------------------------------------------------------------------
    // Test 3: Reverse sorted array (worst case) + stability of out_data
    // -----------------------------------------------------------------------
    run_dut0(64'h00_0A_19_32_64_96_C8_FF, 1'b1, 1'b0, 1'b0);

    // -----------------------------------------------------------------------
    // Test 4: All equal elements (0, non-zero, max 255)
    // -----------------------------------------------------------------------
    run_dut0(64'h2A_2A_2A_2A_2A_2A_2A_2A, 1'b1, 1'b0, 1'b0);
    run_dut0(64'h00_00_00_00_00_00_00_00, 1'b1, 1'b0, 1'b0);
    run_dut0(64'hFF_FF_FF_FF_FF_FF_FF_FF, 1'b1, 1'b0, 1'b0);

    // -----------------------------------------------------------------------
    // Test 5: Duplicates, extremes (0, 255), and MSB-set unsigned values (>=128)
    // -----------------------------------------------------------------------
    run_dut0(64'hFE_01_7F_80_00_FF_00_FF, 1'b1, 1'b0, 1'b0);
    run_dut0(64'h04_05_03_05_02_05_01_05, 1'b1, 1'b0, 1'b0);

    // -----------------------------------------------------------------------
    // Test 6: Single element out of place at extremes
    // -----------------------------------------------------------------------
    run_dut0(64'h07_06_05_04_03_02_01_FF, 1'b1, 1'b0, 1'b0);
    run_dut0(64'h00_07_06_05_04_03_02_01, 1'b1, 1'b0, 1'b0);

    // -----------------------------------------------------------------------
    // Test 7: Corrupt in_data immediately after start pulse (input latching)
    // -----------------------------------------------------------------------
    run_dut0(64'h11_99_22_88_33_77_44_66, 1'b1, 1'b1, 1'b0);

    // -----------------------------------------------------------------------
    // Test 8: Back-to-back sorting operations
    // -----------------------------------------------------------------------
    run_dut0(64'hA5_5A_C3_3C_F0_0F_12_21, 1'b1, 1'b0, 1'b1);
    run_dut0(64'h09_87_65_43_21_FE_DC_BA, 1'b1, 1'b0, 1'b0);

    // -----------------------------------------------------------------------
    // Test 9: Asynchronous reset mid-sort & out_data retention across reset
    // -----------------------------------------------------------------------
    saved_out = out_data;
    @(negedge clk);
    in_data = 64'hDE_AD_BE_EF_CA_FE_BA_BE;
    start   = 1'b1;
    @(posedge clk);
    @(negedge clk);
    start   = 1'b0;

    repeat (20) @(posedge clk);
    #2; // mid-cycle away from clock edges
    rst = 1'b1;
    #1;
    if (done !== 1'b0) begin
      $display("FAIL: [Async Reset Mid-Sort] done not immediately 0 (expected 0, got %b)", done);
      errors = errors + 1;
    end
    if (out_data !== saved_out) begin
      $display("FAIL: [Async Reset Mid-Sort] out_data was modified by reset (expected %h, got %h)", saved_out, out_data);
      errors = errors + 1;
    end

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    // Confirm aborted sort never asserts done and out_data stays untouched
    for (wait_cyc = 0; wait_cyc < 65; wait_cyc = wait_cyc + 1) begin
      @(posedge clk);
      #1;
      if (done !== 1'b0) begin
        $display("FAIL: [Async Reset Mid-Sort] spurious done after reset release at cycle %0d", wait_cyc);
        errors = errors + 1;
      end
      if (out_data !== saved_out) begin
        $display("FAIL: [Async Reset Mid-Sort] out_data changed after reset release (expected %h, got %h)", saved_out, out_data);
        errors = errors + 1;
      end
    end

    // Confirm DUT recovers and sorts normally after mid-sort reset
    run_dut0(64'h55_AA_10_EF_20_CD_30_AB, 1'b1, 1'b0, 1'b0);

    // -----------------------------------------------------------------------
    // Test 10: Asynchronous reset asserted during done == 1 pulse
    // -----------------------------------------------------------------------
    saved_out = ref_sort(64'h90_80_70_60_50_40_30_20, 8, 8);
    @(negedge clk);
    in_data = 64'h90_80_70_60_50_40_30_20;
    start   = 1'b1;
    @(posedge clk);
    @(negedge clk);
    start   = 1'b0;

    saw_done_mid_rst = 1'b0;
    for (wait_cyc = 1; wait_cyc <= 68; wait_cyc = wait_cyc + 1) begin
      @(posedge clk);
      #1;
      if (done === 1'b1) begin
        saw_done_mid_rst = 1'b1;
        if (out_data !== saved_out) begin
          $display("FAIL: [Reset on Done] out_data mismatch before reset (expected %h, got %h)", saved_out, out_data);
          errors = errors + 1;
        end
        #1; // still inside done == 1 cycle
        rst = 1'b1;
        #1;
        if (done !== 1'b0) begin
          $display("FAIL: [Reset on Done] done did not clear asynchronously when rst asserted (expected 0, got %b)", done);
          errors = errors + 1;
        end
        if (out_data !== saved_out) begin
          $display("FAIL: [Reset on Done] out_data altered by reset (expected %h, got %h)", saved_out, out_data);
          errors = errors + 1;
        end
        wait_cyc = 100;
      end
    end
    if (!saw_done_mid_rst) begin
      $display("FAIL: [Reset on Done] timeout waiting for done");
      errors = errors + 1;
    end

    @(negedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);
    run_dut0(64'h01_02_03_04_05_06_07_08, 1'b1, 1'b0, 1'b0);

    // -----------------------------------------------------------------------
    // Test 11: Pseudo-random stress tests on default DUT
    // -----------------------------------------------------------------------
    for (k = 0; k < 15; k = k + 1) begin
      rand_vec = {$random(seed), $random(seed)};
      run_dut0(rand_vec, 1'b1, 1'b0, 1'b0);
    end

    // -----------------------------------------------------------------------
    // Test 12: Parameterized DUT 1 (N = 4, WIDTH = 16)
    // -----------------------------------------------------------------------
    @(negedge clk);
    rst_p1 = 1'b0;
    repeat (2) @(posedge clk);

    run_dut_p1(64'h0001_FFFF_8000_0000, 1'b0);
    run_dut_p1(64'h1234_5678_9ABC_DEF0, 1'b1);
    run_dut_p1(64'h0000_0000_0000_0000, 1'b1);
    run_dut_p1(64'hFFFF_7FFF_8000_0001, 1'b1);
    for (k = 0; k < 5; k = k + 1) begin
      rand_vec = {$random(seed), $random(seed)};
      run_dut_p1(rand_vec, 1'b1);
    end

    // -----------------------------------------------------------------------
    // Test 13: Parameterized DUT 2 (N = 2, WIDTH = 4)
    // -----------------------------------------------------------------------
    @(negedge clk);
    rst_p2 = 1'b0;
    repeat (2) @(posedge clk);

    run_dut_p2(8'h0F);
    run_dut_p2(8'hF0);
    run_dut_p2(8'h77);
    run_dut_p2(8'h87);
    run_dut_p2(8'h00);

    // -----------------------------------------------------------------------
    // Test 14: Parameterized DUT 3 (N = 5, WIDTH = 1)
    // -----------------------------------------------------------------------
    @(negedge clk);
    rst_p3 = 1'b0;
    repeat (2) @(posedge clk);

    run_dut_p3(5'b00000);
    run_dut_p3(5'b11111);
    run_dut_p3(5'b00101);
    run_dut_p3(5'b10101);
    run_dut_p3(5'b00001);

    // -----------------------------------------------------------------------
    // Final Result
    // -----------------------------------------------------------------------
    if (errors == 0)
      $display("PASS");
    else
      $display("FAIL: %0d errors", errors);

    $finish;
  end

endmodule
