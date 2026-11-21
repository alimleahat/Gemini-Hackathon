`timescale 1ns/1ps

module tb;
  reg clk;
  reg rst;
  wire [3:0] ms_hr;
  wire [3:0] ls_hr;
  wire [3:0] ms_min;
  wire [3:0] ls_min;
  wire [3:0] ms_sec;
  wire [3:0] ls_sec;

  integer errors = 0;
  integer cycle;

  // Golden reference state
  reg [3:0] exp_ms_hr;
  reg [3:0] exp_ls_hr;
  reg [3:0] exp_ms_min;
  reg [3:0] exp_ls_min;
  reg [3:0] exp_ms_sec;
  reg [3:0] exp_ls_sec;

  bcd_counter dut (
    .clk    (clk),
    .rst    (rst),
    .ms_hr  (ms_hr),
    .ls_hr  (ls_hr),
    .ms_min (ms_min),
    .ls_min (ls_min),
    .ms_sec (ms_sec),
    .ls_sec (ls_sec)
  );

  // Clock generation: 10 ns period
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task check_outputs;
    input [127:0] tag;
    begin
      if ({ms_hr, ls_hr, ms_min, ls_min, ms_sec, ls_sec} !==
          {exp_ms_hr, exp_ls_hr, exp_ms_min, exp_ls_min, exp_ms_sec, exp_ls_sec}) begin
        $display("FAIL: [%0s] cycle %0d: expected %0d%0d:%0d%0d:%0d%0d, got %0d%0d:%0d%0d:%0d%0d",
                 tag, cycle,
                 exp_ms_hr, exp_ls_hr, exp_ms_min, exp_ls_min, exp_ms_sec, exp_ls_sec,
                 ms_hr, ls_hr, ms_min, ls_min, ms_sec, ls_sec);
        errors = errors + 1;
      end
    end
  endtask

  task step_expected;
    begin
      if (exp_ls_sec < 4'd9) begin
        exp_ls_sec = exp_ls_sec + 4'd1;
      end else begin
        exp_ls_sec = 4'd0;
        if (exp_ms_sec < 4'd5) begin
          exp_ms_sec = exp_ms_sec + 4'd1;
        end else begin
          exp_ms_sec = 4'd0;
          if (exp_ls_min < 4'd9) begin
            exp_ls_min = exp_ls_min + 4'd1;
          end else begin
            exp_ls_min = 4'd0;
            if (exp_ms_min < 4'd5) begin
              exp_ms_min = exp_ms_min + 4'd1;
            end else begin
              exp_ms_min = 4'd0;
              if (exp_ms_hr == 4'd2 && exp_ls_hr == 4'd3) begin
                exp_ms_hr = 4'd0;
                exp_ls_hr = 4'd0;
              end else if (exp_ls_hr < 4'd9) begin
                exp_ls_hr = exp_ls_hr + 4'd1;
              end else begin
                exp_ls_hr = 4'd0;
                exp_ms_hr = exp_ms_hr + 4'd1;
              end
            end
          end
        end
      end
    end
  endtask

  task apply_reset;
    input integer hold_cycles;
    integer i;
    begin
      @(negedge clk);
      rst = 1'b1;
      exp_ms_hr  = 4'd0;
      exp_ls_hr  = 4'd0;
      exp_ms_min = 4'd0;
      exp_ls_min = 4'd0;
      exp_ms_sec = 4'd0;
      exp_ls_sec = 4'd0;
      for (i = 0; i < hold_cycles; i = i + 1) begin
        @(posedge clk);
        #1;
        check_outputs("RESET");
      end
      @(negedge clk);
      rst = 1'b0;
    end
  endtask

  initial begin
    rst = 1'b1;
    cycle = 0;
    exp_ms_hr  = 4'd0;
    exp_ls_hr  = 4'd0;
    exp_ms_min = 4'd0;
    exp_ls_min = 4'd0;
    exp_ms_sec = 4'd0;
    exp_ls_sec = 4'd0;

    // 1. Initial reset check (hold reset across multiple clock edges)
    apply_reset(3);

    // 2. Count to a non-zero value (e.g. 00:01:15 = 75 cycles) and test mid-operation reset
    for (cycle = 1; cycle <= 75; cycle = cycle + 1) begin
      @(posedge clk);
      step_expected();
      #1;
      check_outputs("PRE_RST_COUNT");
    end

    apply_reset(2);

    // 3. Full 24-hour cycle + wraparound verification (86,415 cycles)
    // Covers:
    //  - ls_sec rollover (9 -> 0)
    //  - ms_sec rollover (59 -> 00)
    //  - ls_min rollover (09:59 -> 10:00)
    //  - ms_min rollover (59:59 -> 00:00)
    //  - ls_hr rollover (09:59:59 -> 10:00:00 and 19:59:59 -> 20:00:00)
    //  - 24-hour rollover (23:59:59 -> 00:00:00) and continued counting
    for (cycle = 1; cycle <= 86415; cycle = cycle + 1) begin
      @(posedge clk);
      step_expected();
      #1;
      check_outputs("24H_RUN");
    end

    if (errors == 0) begin
      $display("PASS");
    end else begin
      $display("FAIL: %0d errors", errors);
    end

    $finish;
  end
endmodule
