`timescale 1ns/1ps

module tb;

  // Timing constants per 640x480@60Hz VGA specification
  localparam integer H_ACTIVE = 640;
  localparam integer H_FRONT  = 16;
  localparam integer H_PULSE  = 96;
  localparam integer H_BACK   = 48;
  localparam integer H_TOTAL  = H_ACTIVE + H_FRONT + H_PULSE + H_BACK; // 800

  localparam integer V_ACTIVE = 480;
  localparam integer V_FRONT  = 10;
  localparam integer V_PULSE  = 2;
  localparam integer V_BACK   = 33;
  localparam integer V_TOTAL  = V_ACTIVE + V_FRONT + V_PULSE + V_BACK; // 525

  // DUT inputs
  reg        clock;
  reg        reset;
  reg  [7:0] color_in;

  // DUT outputs
  wire       hsync;
  wire       vsync;
  wire [7:0] red;
  wire [7:0] green;
  wire [7:0] blue;
  wire [9:0] next_x;
  wire [9:0] next_y;
  wire       sync;
  wire       clk;
  wire       blank;

  integer errors = 0;

  // Instantiate DUT with exact module name and port names/widths
  vga_controller dut (
    .clock    (clock),
    .reset    (reset),
    .color_in (color_in),
    .hsync    (hsync),
    .vsync    (vsync),
    .red      (red),
    .green    (green),
    .blue     (blue),
    .next_x   (next_x),
    .next_y   (next_y),
    .sync     (sync),
    .clk      (clk),
    .blank    (blank)
  );

  // 25 MHz clock (40 ns period)
  initial clock = 1'b0;
  always #20 clock = ~clock;

  // Verify clk output tracks clock input directly
  always @(clock) begin
    #1;
    if ($time > 0 && clk !== clock) begin
      if (errors < 20)
        $display("FAIL: clk mismatch at t=%0t: expected %b, got %b", $time, clock, clk);
      errors = errors + 1;
    end
  end

  // Helper task to sync to the first active display cycle after reset release
  task wait_for_active_start;
    input [7:0] exp_r;
    input [7:0] exp_g;
    input [7:0] exp_b;
    integer tries;
    reg found;
    begin
      found = 1'b0;
      for (tries = 0; tries < 5; tries = tries + 1) begin
        @(negedge clock);
        if (red === exp_r && green === exp_g && blue === exp_b &&
            hsync === 1'b1 && vsync === 1'b1) begin
          found = 1'b1;
          tries = 5; // break
        end
      end
      if (!found) begin
        if (errors < 20)
          $display("FAIL: Did not enter active display after reset (got rgb=%h_%h_%h hsync=%b vsync=%b)",
                   red, green, blue, hsync, vsync);
        errors = errors + 1;
      end
    end
  endtask

  // Helper task to check one full horizontal line (800 clocks)
  // Expects caller to be at negedge clock of col=0 on entry,
  // and leaves caller at negedge clock of col=0 of next line on exit.
  task check_line;
    input integer line_idx;
    input [7:0]   exp_r;
    input [7:0]   exp_g;
    input [7:0]   exp_b;
    input         use_color_sweep;
    input [7:0]   next_line_color;
    integer col;
    reg [9:0] x_offset;
    reg       v_act;
    reg       exp_vsync;
    reg [7:0] sweep_val;
    reg [7:0] chk_r, chk_g, chk_b;
    begin
      v_act     = (line_idx < V_ACTIVE);
      exp_vsync = (line_idx >= (V_ACTIVE + V_FRONT) &&
                   line_idx <  (V_ACTIVE + V_FRONT + V_PULSE)) ? 1'b0 : 1'b1;
      x_offset  = 10'd0;

      for (col = 0; col < H_TOTAL; col = col + 1) begin
        // Check sync is always 0
        if (sync !== 1'b0) begin
          if (errors < 20)
            $display("FAIL: line=%0d col=%0d sync expected 0, got %b", line_idx, col, sync);
          errors = errors + 1;
        end

        // Check vsync
        if (vsync !== exp_vsync) begin
          if (errors < 20)
            $display("FAIL: line=%0d col=%0d vsync expected %b, got %b", line_idx, col, exp_vsync, vsync);
          errors = errors + 1;
        end

        // Check hsync according to horizontal timing intervals
        if (col < H_ACTIVE + H_FRONT) begin
          if (hsync !== 1'b1) begin
            if (errors < 20)
              $display("FAIL: line=%0d col=%0d hsync expected 1 (active/front), got %b", line_idx, col, hsync);
            errors = errors + 1;
          end
        end else if (col < H_ACTIVE + H_FRONT + H_PULSE) begin
          if (hsync !== 1'b0) begin
            if (errors < 20)
              $display("FAIL: line=%0d col=%0d hsync expected 0 (sync pulse), got %b", line_idx, col, hsync);
            errors = errors + 1;
          end
        end else begin
          if (hsync !== 1'b1) begin
            if (errors < 20)
              $display("FAIL: line=%0d col=%0d hsync expected 1 (back porch), got %b", line_idx, col, hsync);
            errors = errors + 1;
          end
        end

        // Check blank in definite states (active display => 0, sync pulse => 1)
        if (v_act && col < H_ACTIVE) begin
          if (blank !== 1'b0) begin
            if (errors < 20)
              $display("FAIL: line=%0d col=%0d blank expected 0 during active, got %b", line_idx, col, blank);
            errors = errors + 1;
          end
        end else if (exp_vsync === 1'b0 || (col >= H_ACTIVE + H_FRONT && col < H_ACTIVE + H_FRONT + H_PULSE)) begin
          if (blank !== 1'b1) begin
            if (errors < 20)
              $display("FAIL: line=%0d col=%0d blank expected 1 during sync pulse, got %b", line_idx, col, blank);
            errors = errors + 1;
          end
        end

        // Check RGB outputs
        if (v_act && col < H_ACTIVE) begin
          if (!use_color_sweep) begin
            if (red !== exp_r || green !== exp_g || blue !== exp_b) begin
              if (errors < 20)
                $display("FAIL: line=%0d col=%0d rgb expected %h_%h_%h, got %h_%h_%h",
                         line_idx, col, exp_r, exp_g, exp_b, red, green, blue);
              errors = errors + 1;
            end
          end else begin
            // On odd cycles (2nd cycle of each held color_in), verify exact scaling
            if (col < 512 && (col & 1) == 1) begin
              sweep_val = (col >> 1);
              chk_r = {sweep_val[7:5], 5'd0};
              chk_g = {sweep_val[4:2], 5'd0};
              chk_b = {sweep_val[1:0], 6'd0};
              if (red !== chk_r || green !== chk_g || blue !== chk_b) begin
                if (errors < 20)
                  $display("FAIL: color_in=%h line=%0d col=%0d rgb expected %h_%h_%h, got %h_%h_%h",
                           sweep_val, line_idx, col, chk_r, chk_g, chk_b, red, green, blue);
                errors = errors + 1;
              end
            end else if (col >= 513) begin
              if (red !== 8'hE0 || green !== 8'hE0 || blue !== 8'hC0) begin
                if (errors < 20)
                  $display("FAIL: color_in=FF line=%0d col=%0d rgb expected E0_E0_C0, got %h_%h_%h",
                           line_idx, col, red, green, blue);
                errors = errors + 1;
              end
            end
          end
        end else begin
          // Blanking period: RGB must be zero
          if (red !== 8'd0 || green !== 8'd0 || blue !== 8'd0) begin
            if (errors < 20)
              $display("FAIL: line=%0d col=%0d blanking rgb expected 00_00_00, got %h_%h_%h",
                       line_idx, col, red, green, blue);
            errors = errors + 1;
          end
        end

        // Check next_x and next_y
        if (v_act && col < H_ACTIVE) begin
          if (col == 0) begin
            x_offset = next_x;
            if (x_offset !== 10'd0 && x_offset !== 10'd1) begin
              if (errors < 20)
                $display("FAIL: line=%0d col=0 next_x expected 0 or 1, got %0d", line_idx, next_x);
              errors = errors + 1;
            end
          end else if (col < H_ACTIVE - 1) begin
            if (next_x !== (col[9:0] + x_offset)) begin
              if (errors < 20)
                $display("FAIL: line=%0d col=%0d next_x expected %0d, got %0d",
                         line_idx, col, col + x_offset, next_x);
              errors = errors + 1;
            end
          end else begin
            if (next_x !== 10'd639 && next_x !== 10'd0 && next_x !== 10'd640) begin
              if (errors < 20)
                $display("FAIL: line=%0d col=639 next_x invalid %0d", line_idx, next_x);
              errors = errors + 1;
            end
          end

          if (next_y !== line_idx[9:0]) begin
            if (errors < 20)
              $display("FAIL: line=%0d col=%0d next_y expected %0d, got %0d",
                       line_idx, col, line_idx, next_y);
            errors = errors + 1;
          end
        end else begin
          if (next_x !== 10'd0) begin
            if (errors < 20)
              $display("FAIL: line=%0d col=%0d blanking next_x expected 0, got %0d",
                       line_idx, col, next_x);
            errors = errors + 1;
          end
          if (!v_act && next_y !== 10'd0) begin
            if (errors < 20)
              $display("FAIL: line=%0d col=%0d vblank next_y expected 0, got %0d",
                       line_idx, col, next_y);
            errors = errors + 1;
          end
        end

        // Update color_in at negedge when sweeping or preparing next line
        if (use_color_sweep) begin
          if (col < 511 && (col & 1) == 1)
            color_in = ((col >> 1) + 1);
          else if (col == 511)
            color_in = 8'hFF;
          else if (col == 639)
            color_in = next_line_color;
        end else if (col == H_TOTAL - 1) begin
          color_in = next_line_color;
        end

        @(negedge clock);
      end
    end
  endtask

  integer ln;
  integer k;

  initial begin
    // Phase 1: Initial reset
    reset    = 1'b1;
    color_in = 8'h00;
    repeat (5) @(negedge clock);

    if (sync !== 1'b0) begin
      $display("FAIL: sync expected 0 during reset, got %b", sync);
      errors = errors + 1;
    end

    // Release reset and drive test color 8'hF6 -> R=E0, G=A0, B=80
    reset    = 1'b0;
    color_in = 8'hF6;
    wait_for_active_start(8'hE0, 8'hA0, 8'h80);

    // Phase 2: Check Line 0 (with 8'hF6) and prepare color_in=0 for Line 1 sweep
    check_line(0, 8'hE0, 8'hA0, 8'h80, 1'b0, 8'h00);

    // Line 1: Sweep all 256 color_in values (0..255), then prepare 8'hB9 (R=A0, G=C0, B=40)
    check_line(1, 8'h00, 8'h00, 8'h00, 1'b1, 8'hB9);

    // Phase 3: Check remaining 523 lines of Frame 1 (lines 2..524)
    for (ln = 2; ln < V_TOTAL; ln = ln + 1) begin
      check_line(ln, 8'hA0, 8'hC0, 8'h40, 1'b0, 8'hB9);
    end

    // Check Frame 2, Line 0 to verify frame wrap-around
    check_line(0, 8'hA0, 8'hC0, 8'h40, 1'b0, 8'hB9);

    // Phase 4: Advance partway into Frame 2 Line 1, then assert asynchronous reset
    for (k = 0; k < 100; k = k + 1)
      @(negedge clock);

    #5; // Assert reset asynchronously between clock edges
    reset    = 1'b1;
    color_in = 8'h00;
    repeat (3) @(negedge clock);

    if (sync !== 1'b0) begin
      if (errors < 20)
        $display("FAIL: sync expected 0 after async reset, got %b", sync);
      errors = errors + 1;
    end

    // Release reset and confirm clean restart at Line 0, Pixel 0
    reset    = 1'b0;
    color_in = 8'hF6;
    wait_for_active_start(8'hE0, 8'hA0, 8'h80);

    if (next_y !== 10'd0 || next_x > 10'd1) begin
      if (errors < 20)
        $display("FAIL: post-reset coordinates expected (0..1, 0), got (%0d, %0d)", next_x, next_y);
      errors = errors + 1;
    end

    check_line(0, 8'hE0, 8'hA0, 8'h80, 1'b0, 8'hB9);

    // Phase 5: Report results
    if (errors == 0)
      $display("PASS");
    else
      $display("FAIL: %0d errors", errors);

    $finish;
  end

endmodule
