`timescale 1ns/1ps

module tb;

  localparam integer TOTAL_SPACES = 12;
  localparam integer WIDTH = $clog2(TOTAL_SPACES);

  reg clk;
  reg reset;
  reg vehicle_entry_sensor;
  reg vehicle_exit_sensor;

  wire [WIDTH-1:0] available_spaces;
  wire [WIDTH-1:0] count_car;
  wire led_status;
  wire [6:0] seven_seg_display_available_tens;
  wire [6:0] seven_seg_display_available_units;
  wire [6:0] seven_seg_display_count_tens;
  wire [6:0] seven_seg_display_count_units;

  integer errors = 0;
  integer i;

  car_parking_system #(
    .TOTAL_SPACES(TOTAL_SPACES)
  ) dut (
    .clk(clk),
    .reset(reset),
    .vehicle_entry_sensor(vehicle_entry_sensor),
    .vehicle_exit_sensor(vehicle_exit_sensor),
    .available_spaces(available_spaces),
    .count_car(count_car),
    .led_status(led_status),
    .seven_seg_display_available_tens(seven_seg_display_available_tens),
    .seven_seg_display_available_units(seven_seg_display_available_units),
    .seven_seg_display_count_tens(seven_seg_display_count_tens),
    .seven_seg_display_count_units(seven_seg_display_count_units)
  );

  // 100 MHz clock (10 ns period)
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // 7-segment encoder: MSB = segment A, LSB = segment G (active-high)
  function [6:0] seg7;
    input integer digit;
    begin
      case (digit)
        0: seg7 = 7'b1111110;
        1: seg7 = 7'b0110000;
        2: seg7 = 7'b1101101;
        3: seg7 = 7'b1111001;
        4: seg7 = 7'b0110011;
        5: seg7 = 7'b1011011;
        6: seg7 = 7'b1011111;
        7: seg7 = 7'b1110000;
        8: seg7 = 7'b1111111;
        9: seg7 = 7'b1111011;
        default: seg7 = 7'b0000000;
      endcase
    end
  endfunction

  task check_outputs;
    input integer exp_avail;
    input integer exp_count;
    input integer test_id;
    reg exp_led;
    reg [6:0] exp_avail_tens;
    reg [6:0] exp_avail_units;
    reg [6:0] exp_count_tens;
    reg [6:0] exp_count_units;
    begin
      exp_led         = (exp_avail > 0) ? 1'b1 : 1'b0;
      exp_avail_tens  = seg7(exp_avail / 10);
      exp_avail_units = seg7(exp_avail % 10);
      exp_count_tens  = seg7(exp_count / 10);
      exp_count_units = seg7(exp_count % 10);

      if (available_spaces !== exp_avail[WIDTH-1:0]) begin
        $display("FAIL [test %0d @ %0t]: available_spaces expected %0d, got %0d",
                 test_id, $time, exp_avail, available_spaces);
        errors = errors + 1;
      end

      if (count_car !== exp_count[WIDTH-1:0]) begin
        $display("FAIL [test %0d @ %0t]: count_car expected %0d, got %0d",
                 test_id, $time, exp_count, count_car);
        errors = errors + 1;
      end

      if (led_status !== exp_led) begin
        $display("FAIL [test %0d @ %0t]: led_status expected %b, got %b",
                 test_id, $time, exp_led, led_status);
        errors = errors + 1;
      end

      if (seven_seg_display_available_tens !== exp_avail_tens) begin
        $display("FAIL [test %0d @ %0t]: available_tens 7-seg expected %b (digit %0d), got %b",
                 test_id, $time, exp_avail_tens, exp_avail / 10, seven_seg_display_available_tens);
        errors = errors + 1;
      end

      if (seven_seg_display_available_units !== exp_avail_units) begin
        $display("FAIL [test %0d @ %0t]: available_units 7-seg expected %b (digit %0d), got %b",
                 test_id, $time, exp_avail_units, exp_avail % 10, seven_seg_display_available_units);
        errors = errors + 1;
      end

      if (seven_seg_display_count_tens !== exp_count_tens) begin
        $display("FAIL [test %0d @ %0t]: count_tens 7-seg expected %b (digit %0d), got %b",
                 test_id, $time, exp_count_tens, exp_count / 10, seven_seg_display_count_tens);
        errors = errors + 1;
      end

      if (seven_seg_display_count_units !== exp_count_units) begin
        $display("FAIL [test %0d @ %0t]: count_units 7-seg expected %b (digit %0d), got %b",
                 test_id, $time, exp_count_units, exp_count % 10, seven_seg_display_count_units);
        errors = errors + 1;
      end
    end
  endtask

  task check_invariants;
    input integer test_id;
    reg exp_led;
    begin
      if (^available_spaces === 1'bx || ^count_car === 1'bx || ^led_status === 1'bx) begin
        $display("FAIL [test %0d @ %0t]: X/Z detected on outputs (avail=%b, count=%b, led=%b)",
                 test_id, $time, available_spaces, count_car, led_status);
        errors = errors + 1;
      end else begin
        if ((available_spaces + count_car) !== TOTAL_SPACES) begin
          $display("FAIL [test %0d @ %0t]: invariant available_spaces(%0d) + count_car(%0d) != %0d",
                   test_id, $time, available_spaces, count_car, TOTAL_SPACES);
          errors = errors + 1;
        end
        if (available_spaces > TOTAL_SPACES || count_car > TOTAL_SPACES) begin
          $display("FAIL [test %0d @ %0t]: out of range (avail=%0d, count=%0d)",
                   test_id, $time, available_spaces, count_car);
          errors = errors + 1;
        end
        exp_led = (available_spaces > 0) ? 1'b1 : 1'b0;
        if (led_status !== exp_led) begin
          $display("FAIL [test %0d @ %0t]: led_status expected %b for avail=%0d, got %b",
                   test_id, $time, exp_led, available_spaces, led_status);
          errors = errors + 1;
        end
        check_outputs(available_spaces, count_car, test_id);
      end
    end
  endtask

  initial begin
    reset = 1'b0;
    vehicle_entry_sensor = 1'b0;
    vehicle_exit_sensor  = 1'b0;

    // ------------------------------------------------------------------
    // Test 1: Asynchronous reset before any clock edge (while clk == 0)
    // ------------------------------------------------------------------
    #2;
    reset = 1'b1;
    #2; // t = 4ns (before first posedge at 5ns)
    check_outputs(TOTAL_SPACES, 0, 1);

    // Hold reset across two clock edges, then release at negedge
    @(negedge clk);
    @(negedge clk);
    reset = 1'b0;
    @(posedge clk); #1;
    check_outputs(TOTAL_SPACES, 0, 2);

    // ------------------------------------------------------------------
    // Test 2: Single entry then single exit (Example Operation sequence)
    // ------------------------------------------------------------------
    @(negedge clk);
    vehicle_entry_sensor = 1'b1;
    vehicle_exit_sensor  = 1'b0;
    @(posedge clk); #1;
    check_outputs(TOTAL_SPACES - 1, 1, 3);

    @(negedge clk);
    vehicle_entry_sensor = 1'b0;
    vehicle_exit_sensor  = 1'b1;
    @(posedge clk); #1;
    check_outputs(TOTAL_SPACES, 0, 4);

    @(negedge clk);
    vehicle_entry_sensor = 1'b0;
    vehicle_exit_sensor  = 1'b0;
    @(posedge clk); #1;
    check_outputs(TOTAL_SPACES, 0, 5);

    // ------------------------------------------------------------------
    // Test 3: Exit when parking lot is empty (must not underflow)
    // ------------------------------------------------------------------
    for (i = 0; i < 3; i = i + 1) begin
      @(negedge clk);
      vehicle_entry_sensor = 1'b0;
      vehicle_exit_sensor  = 1'b1;
      @(posedge clk); #1;
      check_outputs(TOTAL_SPACES, 0, 6);
    end
    @(negedge clk);
    vehicle_exit_sensor = 1'b0;
    @(posedge clk); #1;
    check_outputs(TOTAL_SPACES, 0, 7);

    // ------------------------------------------------------------------
    // Test 4: Fill parking lot from 0 to TOTAL_SPACES (12)
    // ------------------------------------------------------------------
    for (i = 1; i <= TOTAL_SPACES; i = i + 1) begin
      @(negedge clk);
      vehicle_entry_sensor = 1'b1;
      vehicle_exit_sensor  = 1'b0;
      @(posedge clk); #1;
      check_outputs(TOTAL_SPACES - i, i, 100 + i);

      @(negedge clk);
      vehicle_entry_sensor = 1'b0;
      vehicle_exit_sensor  = 1'b0;
      @(posedge clk); #1;
      check_outputs(TOTAL_SPACES - i, i, 200 + i);
    end

    // ------------------------------------------------------------------
    // Test 5: Entry denied when parking lot is full
    // ------------------------------------------------------------------
    for (i = 0; i < 4; i = i + 1) begin
      @(negedge clk);
      vehicle_entry_sensor = 1'b1;
      vehicle_exit_sensor  = 1'b0;
      @(posedge clk); #1;
      check_outputs(0, TOTAL_SPACES, 300 + i);
    end
    @(negedge clk);
    vehicle_entry_sensor = 1'b0;
    @(posedge clk); #1;
    check_outputs(0, TOTAL_SPACES, 310);

    // ------------------------------------------------------------------
    // Test 6: Exit from full state, then re-enter to full state
    // ------------------------------------------------------------------
    @(negedge clk);
    vehicle_entry_sensor = 1'b0;
    vehicle_exit_sensor  = 1'b1;
    @(posedge clk); #1;
    check_outputs(1, TOTAL_SPACES - 1, 320);

    @(negedge clk);
    vehicle_entry_sensor = 1'b1;
    vehicle_exit_sensor  = 1'b0;
    @(posedge clk); #1;
    check_outputs(0, TOTAL_SPACES, 321);

    @(negedge clk);
    vehicle_entry_sensor = 1'b0;
    vehicle_exit_sensor  = 1'b0;
    @(posedge clk); #1;
    check_outputs(0, TOTAL_SPACES, 322);

    // ------------------------------------------------------------------
    // Test 7: Empty parking lot completely from 12 down to 0
    // ------------------------------------------------------------------
    for (i = 1; i <= TOTAL_SPACES; i = i + 1) begin
      @(negedge clk);
      vehicle_entry_sensor = 1'b0;
      vehicle_exit_sensor  = 1'b1;
      @(posedge clk); #1;
      check_outputs(i, TOTAL_SPACES - i, 400 + i);

      @(negedge clk);
      vehicle_entry_sensor = 1'b0;
      vehicle_exit_sensor  = 1'b0;
      @(posedge clk); #1;
      check_outputs(i, TOTAL_SPACES - i, 500 + i);
    end

    // ------------------------------------------------------------------
    // Test 8: Simultaneous entry & exit sensors (invariant check)
    // ------------------------------------------------------------------
    for (i = 1; i <= 3; i = i + 1) begin
      @(negedge clk);
      vehicle_entry_sensor = 1'b1;
      vehicle_exit_sensor  = 1'b0;
      @(posedge clk); #1;
      check_outputs(TOTAL_SPACES - i, i, 600 + i);
    end

    for (i = 0; i < 2; i = i + 1) begin
      @(negedge clk);
      vehicle_entry_sensor = 1'b1;
      vehicle_exit_sensor  = 1'b1;
      @(posedge clk); #1;
      check_invariants(610 + i);
    end

    @(negedge clk);
    vehicle_entry_sensor = 1'b0;
    vehicle_exit_sensor  = 1'b0;
    @(posedge clk); #1;
    check_invariants(620);

    // ------------------------------------------------------------------
    // Test 9: Asynchronous reset from Full state (between clock edges)
    // ------------------------------------------------------------------
    while (count_car < TOTAL_SPACES) begin
      @(negedge clk);
      vehicle_entry_sensor = 1'b1;
      vehicle_exit_sensor  = 1'b0;
      @(posedge clk); #1;
    end
    check_outputs(0, TOTAL_SPACES, 700);

    @(negedge clk);
    vehicle_entry_sensor = 1'b0;
    #1;
    reset = 1'b1;
    #2; // Still before next posedge clk
    check_outputs(TOTAL_SPACES, 0, 701);

    @(posedge clk); #1;
    check_outputs(TOTAL_SPACES, 0, 702);

    @(negedge clk);
    reset = 1'b0;
    @(posedge clk); #1;
    check_outputs(TOTAL_SPACES, 0, 703);

    // ------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------
    if (errors == 0) begin
      $display("PASS");
    end else begin
      $display("FAIL: %0d errors", errors);
    end
    $finish;
  end

endmodule
