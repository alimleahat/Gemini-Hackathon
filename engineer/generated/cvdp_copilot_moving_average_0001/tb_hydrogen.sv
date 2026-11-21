`timescale 1ns/1ps

module tb;

  reg         clk;
  reg         reset;
  reg  [11:0] data_in;
  wire [11:0] data_out;

  integer errors = 0;
  integer cycle_cnt = 0;
  integer seed = 32'hCAFE_BABE;
  integer idx;

  reg [11:0] ref_buf [0:7];

  moving_average dut (
    .clk      (clk),
    .reset    (reset),
    .data_in  (data_in),
    .data_out (data_out)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task clear_ref_buf;
    integer k;
    begin
      for (k = 0; k < 8; k = k + 1) begin
        ref_buf[k] = 12'd0;
      end
    end
  endtask

  task apply_reset;
    input integer num_cycles;
    input [11:0]  din_during_rst;
    integer k;
    begin
      for (k = 0; k < num_cycles; k = k + 1) begin
        @(negedge clk);
        reset   = 1'b1;
        data_in = din_during_rst;
        @(posedge clk);
        #1;
        clear_ref_buf();
        if (data_out !== 12'd0) begin
          $display("FAIL: Reset cycle %0d expected data_out=0, got %0d (0x%03h)", k, data_out, data_out);
          errors = errors + 1;
        end
      end
    end
  endtask

  task step_sample;
    input [11:0] din;
    integer j;
    reg [14:0] ref_sum;
    reg [11:0] exp_out;
    begin
      @(negedge clk);
      reset   = 1'b0;
      data_in = din;
      @(posedge clk);
      #1;
      cycle_cnt = cycle_cnt + 1;

      for (j = 7; j > 0; j = j - 1) begin
        ref_buf[j] = ref_buf[j - 1];
      end
      ref_buf[0] = din;

      ref_sum = 15'd0;
      for (j = 0; j < 8; j = j + 1) begin
        ref_sum = ref_sum + {3'd0, ref_buf[j]};
      end
      exp_out = ref_sum[14:3];

      if (data_out !== exp_out) begin
        $display("FAIL: cycle=%0d data_in=%0d expected=%0d got=%0d", cycle_cnt, din, exp_out, data_out);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    reset   = 1'b1;
    data_in = 12'd0;
    clear_ref_buf();

    // 1. Initial reset with non-zero data_in
    apply_reset(3, 12'hFFF);

    // 2. Startup edge condition (< 8 samples after reset) & truncation check
    step_sample(12'd7);    // sum=7,   avg=0
    step_sample(12'd8);    // sum=15,  avg=1
    step_sample(12'd17);   // sum=32,  avg=4
    step_sample(12'd1);    // sum=33,  avg=4
    step_sample(12'd2);    // sum=35,  avg=4
    step_sample(12'd5);    // sum=40,  avg=5
    step_sample(12'd24);   // sum=64,  avg=8
    step_sample(12'd16);   // sum=80,  avg=10 (full 8 samples)

    // 3. Sliding window eviction (samples 9..16)
    step_sample(12'd87);   // evicts 7  -> sum=160, avg=20
    step_sample(12'd0);    // evicts 8  -> sum=152, avg=19
    step_sample(12'd17);   // evicts 17 -> sum=152, avg=19
    step_sample(12'd9);    // evicts 1  -> sum=160, avg=20

    // 4. All zeros
    for (idx = 0; idx < 10; idx = idx + 1) begin
      step_sample(12'd0);
    end

    // 5. Impulse response: verify exact window depth = 8
    step_sample(12'd4095); // 4095 / 8 = 511
    for (idx = 0; idx < 10; idx = idx + 1) begin
      step_sample(12'd0);  // stays 511 for 7 more cycles, then drops to 0
    end

    // 6. Maximum value saturation / 15-bit sum overflow check
    for (idx = 0; idx < 12; idx = idx + 1) begin
      step_sample(12'd4095);
    end

    // 7. Synchronous reset check while output is non-zero (4095)
    @(negedge clk);
    reset   = 1'b1;
    data_in = 12'd4095;
    #1;
    if (data_out !== 12'd4095) begin
      $display("FAIL: Reset acted asynchronously before posedge clk: expected 4095, got %0d", data_out);
      errors = errors + 1;
    end
    @(posedge clk);
    #1;
    clear_ref_buf();
    if (data_out !== 12'd0) begin
      $display("FAIL: Mid-stream reset failed to clear data_out: expected 0, got %0d", data_out);
      errors = errors + 1;
    end

    // 8. Verify buffer was completely cleared on mid-stream reset
    step_sample(12'd16); // must be 16/8 = 2, no residual 4095 samples
    step_sample(12'd24); // must be (16+24)/8 = 5

    // 9. Alternating extremes (0 and 4095) and walking-ones
    for (idx = 0; idx < 16; idx = idx + 1) begin
      step_sample((idx % 2 == 0) ? 12'd4095 : 12'd0);
    end
    for (idx = 0; idx < 12; idx = idx + 1) begin
      step_sample(12'd1 << idx);
    end

    // 10. Pseudo-random continuous stream
    for (idx = 0; idx < 200; idx = idx + 1) begin
      step_sample($random(seed) & 12'hFFF);
    end

    // 11. Second mid-stream reset followed by short stream
    apply_reset(1, 12'd1234);
    for (idx = 0; idx < 16; idx = idx + 1) begin
      step_sample($random(seed) & 12'hFFF);
    end

    if (errors == 0) begin
      $display("PASS");
    end else begin
      $display("FAIL: %0d errors", errors);
    end

    $finish;
  end

endmodule
