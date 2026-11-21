`timescale 1ns/1ps

module tb;

  localparam integer CLK_PERIOD = 10;
  localparam integer HALF_CLK   = 5;

  integer errors = 0;

  // Clock & Reset
  reg pclk;
  reg preset_n;

  // -------------------------------------------------------------------------
  // DUT 1: Default GPIO_WIDTH = 8
  // -------------------------------------------------------------------------
  reg         psel;
  reg  [7:2]  paddr;
  reg         penable;
  reg         pwrite;
  reg  [31:0] pwdata;
  reg  [7:0]  gpio_in;

  wire [31:0] prdata;
  wire        pready;
  wire        pslverr;
  wire [7:0]  gpio_out;
  wire [7:0]  gpio_enable;
  wire [7:0]  gpio_int;
  wire        comb_int;

  cvdp_copilot_apb_gpio dut (
    .pclk        (pclk),
    .preset_n    (preset_n),
    .psel        (psel),
    .paddr       (paddr),
    .penable     (penable),
    .pwrite      (pwrite),
    .pwdata      (pwdata),
    .gpio_in     (gpio_in),
    .prdata      (prdata),
    .pready      (pready),
    .pslverr     (pslverr),
    .gpio_out    (gpio_out),
    .gpio_enable (gpio_enable),
    .gpio_int    (gpio_int),
    .comb_int    (comb_int)
  );

  // -------------------------------------------------------------------------
  // DUT 2: Parameterized GPIO_WIDTH = 16
  // -------------------------------------------------------------------------
  reg         psel16;
  reg  [7:2]  paddr16;
  reg         penable16;
  reg         pwrite16;
  reg  [31:0] pwdata16;
  reg  [15:0] gpio_in16;

  wire [31:0] prdata16;
  wire        pready16;
  wire        pslverr16;
  wire [15:0] gpio_out16;
  wire [15:0] gpio_enable16;
  wire [15:0] gpio_int16;
  wire        comb_int16;

  cvdp_copilot_apb_gpio #(
    .GPIO_WIDTH(16)
  ) dut16 (
    .pclk        (pclk),
    .preset_n    (preset_n),
    .psel        (psel16),
    .paddr       (paddr16),
    .penable     (penable16),
    .pwrite      (pwrite16),
    .pwdata      (pwdata16),
    .gpio_in     (gpio_in16),
    .prdata      (prdata16),
    .pready      (pready16),
    .pslverr     (pslverr16),
    .gpio_out    (gpio_out16),
    .gpio_enable (gpio_enable16),
    .gpio_int    (gpio_int16),
    .comb_int    (comb_int16)
  );

  // Clock generation
  initial begin
    pclk = 1'b0;
    forever #HALF_CLK pclk = ~pclk;
  end

  // Watchdog timeout
  initial begin
    #100000;
    $display("FAIL: Simulation timeout exceeded");
    errors = errors + 1;
    $finish;
  end

  // Continuous invariant checks out of reset
  always @(negedge pclk) begin
    if (preset_n === 1'b1) begin
      if (pslverr !== 1'b0) begin
        $display("FAIL: dut pslverr expected 0, got %b at time %0t", pslverr, $time);
        errors = errors + 1;
      end
      if (pready !== 1'b1) begin
        $display("FAIL: dut pready expected 1, got %b at time %0t", pready, $time);
        errors = errors + 1;
      end
      if (comb_int !== (|gpio_int)) begin
        $display("FAIL: dut comb_int (%b) != |gpio_int (%b) at time %0t", comb_int, gpio_int, $time);
        errors = errors + 1;
      end

      if (pslverr16 !== 1'b0) begin
        $display("FAIL: dut16 pslverr expected 0, got %b at time %0t", pslverr16, $time);
        errors = errors + 1;
      end
      if (pready16 !== 1'b1) begin
        $display("FAIL: dut16 pready expected 1, got %b at time %0t", pready16, $time);
        errors = errors + 1;
      end
      if (comb_int16 !== (|gpio_int16)) begin
        $display("FAIL: dut16 comb_int (%b) != |gpio_int (%b) at time %0t", comb_int16, gpio_int16, $time);
        errors = errors + 1;
      end
    end
  end

  // -------------------------------------------------------------------------
  // APB Helper Tasks (DUT 1)
  // -------------------------------------------------------------------------
  task apb_write;
    input [7:0]  byte_addr;
    input [31:0] data;
    begin
      @(negedge pclk);
      psel    = 1'b1;
      penable = 1'b0;
      pwrite  = 1'b1;
      paddr   = byte_addr[7:2];
      pwdata  = data;
      @(posedge pclk);
      @(negedge pclk);
      penable = 1'b1;
      @(posedge pclk);
      if (pready !== 1'b1 || pslverr !== 1'b0) begin
        $display("FAIL: APB write handshake error at addr 0x%02h (pready=%b, pslverr=%b)", byte_addr, pready, pslverr);
        errors = errors + 1;
      end
      @(negedge pclk);
      psel    = 1'b0;
      penable = 1'b0;
      pwrite  = 1'b0;
      paddr   = 6'h00;
      pwdata  = 32'h0;
    end
  endtask

  task apb_read;
    input  [7:0]  byte_addr;
    output [31:0] rdata;
    begin
      @(negedge pclk);
      psel    = 1'b1;
      penable = 1'b0;
      pwrite  = 1'b0;
      paddr   = byte_addr[7:2];
      @(posedge pclk);
      @(negedge pclk);
      penable = 1'b1;
      #(HALF_CLK - 1);
      if (pready !== 1'b1 || pslverr !== 1'b0) begin
        $display("FAIL: APB read handshake error at addr 0x%02h (pready=%b, pslverr=%b)", byte_addr, pready, pslverr);
        errors = errors + 1;
      end
      rdata = prdata;
      @(posedge pclk);
      @(negedge pclk);
      psel    = 1'b0;
      penable = 1'b0;
      paddr   = 6'h00;
    end
  endtask

  task check_reg;
    input [7:0]  byte_addr;
    input [31:0] expected;
    input [31:0] mask;
    reg   [31:0] got;
    begin
      apb_read(byte_addr, got);
      if ((got & mask) !== (expected & mask)) begin
        $display("FAIL: Reg 0x%02h mismatch - expected 0x%08h, got 0x%08h (mask 0x%08h)",
                 byte_addr, expected & mask, got & mask, mask);
        errors = errors + 1;
      end
    end
  endtask

  // -------------------------------------------------------------------------
  // APB Helper Tasks (DUT 2 - 16-bit)
  // -------------------------------------------------------------------------
  task apb16_write;
    input [7:0]  byte_addr;
    input [31:0] data;
    begin
      @(negedge pclk);
      psel16    = 1'b1;
      penable16 = 1'b0;
      pwrite16  = 1'b1;
      paddr16   = byte_addr[7:2];
      pwdata16  = data;
      @(posedge pclk);
      @(negedge pclk);
      penable16 = 1'b1;
      @(posedge pclk);
      @(negedge pclk);
      psel16    = 1'b0;
      penable16 = 1'b0;
      pwrite16  = 1'b0;
      paddr16   = 6'h00;
      pwdata16  = 32'h0;
    end
  endtask

  task apb16_read;
    input  [7:0]  byte_addr;
    output [31:0] rdata;
    begin
      @(negedge pclk);
      psel16    = 1'b1;
      penable16 = 1'b0;
      pwrite16  = 1'b0;
      paddr16   = byte_addr[7:2];
      @(posedge pclk);
      @(negedge pclk);
      penable16 = 1'b1;
      #(HALF_CLK - 1);
      rdata = prdata16;
      @(posedge pclk);
      @(negedge pclk);
      psel16    = 1'b0;
      penable16 = 1'b0;
      paddr16   = 6'h00;
    end
  endtask

  // -------------------------------------------------------------------------
  // Main Test Sequence
  // -------------------------------------------------------------------------
  integer i, t_idx, p_idx, k;
  reg [31:0] rdata;
  reg        t_level, t_edge;
  reg        p_high, p_low;
  integer    cnt_lvl_hi, cnt_lvl_lo, cnt_edg_ri, cnt_edg_fa;
  reg        t_lvl_hi, t_lvl_lo, t_edg_ri, t_edg_fa;
  reg        p_lvl_hi, p_lvl_lo, p_edg_ri, p_edg_fa;
  reg        steady_low_init, steady_high_after, steady_low_after;
  reg        saw_rise, saw_fall;
  reg [7:0]  seen_edge_int;

  initial begin
    // Initialize inputs
    preset_n  = 1'b0;
    psel      = 1'b0;
    paddr     = 6'h00;
    penable   = 1'b0;
    pwrite    = 1'b0;
    pwdata    = 32'h0;
    gpio_in   = 8'h00;

    psel16    = 1'b0;
    paddr16   = 6'h00;
    penable16 = 1'b0;
    pwrite16  = 1'b0;
    pwdata16  = 32'h0;
    gpio_in16 = 16'h0000;

    // -----------------------------------------------------------------------
    // TEST 1: Initial Reset Behavior
    // -----------------------------------------------------------------------
    #2;
    if (gpio_out !== 8'h00 || gpio_enable !== 8'h00 || gpio_int !== 8'h00 ||
        comb_int !== 1'b0 || pslverr !== 1'b0) begin
      $display("FAIL: Async reset outputs not 0 on dut (out=%h en=%h int=%h comb=%b err=%b)",
               gpio_out, gpio_enable, gpio_int, comb_int, pslverr);
      errors = errors + 1;
    end
    if (gpio_out16 !== 16'h0000 || gpio_enable16 !== 16'h0000 || gpio_int16 !== 16'h0000 ||
        comb_int16 !== 1'b0 || pslverr16 !== 1'b0) begin
      $display("FAIL: Async reset outputs not 0 on dut16");
      errors = errors + 1;
    end

    repeat (3) @(posedge pclk);
    @(negedge pclk);
    preset_n = 1'b1;
    @(posedge pclk);

    check_reg(8'h00, 32'h0, 32'hFFFF_FFFF);
    check_reg(8'h04, 32'h0, 32'hFFFF_FFFF);
    check_reg(8'h08, 32'h0, 32'hFFFF_FFFF);
    check_reg(8'h0C, 32'h0, 32'hFFFF_FFFF);
    check_reg(8'h10, 32'h0, 32'hFFFF_FFFF);
    check_reg(8'h14, 32'h0, 32'hFFFF_FFFF);
    check_reg(8'h18, 32'h0, 32'hFFFF_FFFF);

    // -----------------------------------------------------------------------
    // TEST 2: Register R/W, GPIO Out, and GPIO Enable
    // -----------------------------------------------------------------------
    apb_write(8'h04, 32'h0000_00A5);
    if (gpio_out !== 8'hA5) begin
      $display("FAIL: gpio_out expected 0xA5, got 0x%02h", gpio_out);
      errors = errors + 1;
    end
    check_reg(8'h04, 32'h0000_00A5, 32'h0000_00FF);

    apb_write(8'h04, 32'h0000_005A);
    if (gpio_out !== 8'h5A) begin
      $display("FAIL: gpio_out expected 0x5A, got 0x%02h", gpio_out);
      errors = errors + 1;
    end
    check_reg(8'h04, 32'h0000_005A, 32'h0000_00FF);

    apb_write(8'h08, 32'h0000_003C);
    if (gpio_enable !== 8'h3C) begin
      $display("FAIL: gpio_enable expected 0x3C, got 0x%02h", gpio_enable);
      errors = errors + 1;
    end
    check_reg(8'h08, 32'h0000_003C, 32'h0000_00FF);

    apb_write(8'h08, 32'h0000_00FF);
    if (gpio_enable !== 8'hFF) begin
      $display("FAIL: gpio_enable expected 0xFF, got 0x%02h", gpio_enable);
      errors = errors + 1;
    end

    apb_write(8'h10, 32'h0000_0055);
    check_reg(8'h10, 32'h0000_0055, 32'h0000_00FF);

    apb_write(8'h14, 32'h0000_00AA);
    check_reg(8'h14, 32'h0000_00AA, 32'h0000_00FF);

    apb_write(8'h0C, 32'h0000_0000);
    check_reg(8'h0C, 32'h0000_0000, 32'h0000_00FF);

    // -----------------------------------------------------------------------
    // TEST 3: Read-Only Registers, Undefined Addresses, Invalid APB Phases, B2B
    // -----------------------------------------------------------------------
    // Write attempts to RO registers 0x00 and 0x18
    apb_write(8'h00, 32'hDEAD_BEEF);
    check_reg(8'h00, 32'h0000_0000, 32'hFFFF_FFFF);

    apb_write(8'h18, 32'hDEAD_BEEF);
    check_reg(8'h18, 32'h0000_0000, 32'hFFFF_FFFF);

    // Undefined addresses: writes ignored, reads return 0, pslverr=0
    apb_write(8'h1C, 32'hFFFF_FFFF);
    apb_write(8'h20, 32'h1234_5678);
    apb_write(8'h3C, 32'hCAFE_BABE);
    apb_write(8'hFC, 32'hA5A5_5A5A);

    check_reg(8'h1C, 32'h0000_0000, 32'hFFFF_FFFF);
    check_reg(8'h20, 32'h0000_0000, 32'hFFFF_FFFF);
    check_reg(8'h3C, 32'h0000_0000, 32'hFFFF_FFFF);
    check_reg(8'hFC, 32'h0000_0000, 32'hFFFF_FFFF);

    // Verify defined registers remained intact
    check_reg(8'h04, 32'h0000_005A, 32'h0000_00FF);
    check_reg(8'h08, 32'h0000_00FF, 32'h0000_00FF);
    check_reg(8'h10, 32'h0000_0055, 32'h0000_00FF);
    check_reg(8'h14, 32'h0000_00AA, 32'h0000_00FF);

    // Attempt write with psel = 0
    @(negedge pclk);
    psel    = 1'b0;
    penable = 1'b1;
    pwrite  = 1'b1;
    paddr   = 6'h01; // 0x04
    pwdata  = 32'h0000_00E1;
    @(posedge pclk);
    @(negedge pclk);
    penable = 1'b0;
    pwrite  = 1'b0;
    paddr   = 6'h00;
    pwdata  = 32'h0;
    if (gpio_out !== 8'h5A) begin
      $display("FAIL: Write occurred while psel=0 (gpio_out=%h)", gpio_out);
      errors = errors + 1;
    end

    // Attempt SETUP without ACCESS
    @(negedge pclk);
    psel    = 1'b1;
    penable = 1'b0;
    pwrite  = 1'b1;
    paddr   = 6'h01; // 0x04
    pwdata  = 32'h0000_00E1;
    @(posedge pclk);
    @(negedge pclk);
    psel    = 1'b0;
    pwrite  = 1'b0;
    paddr   = 6'h00;
    pwdata  = 32'h0;
    if (gpio_out !== 8'h5A) begin
      $display("FAIL: Write occurred during SETUP without ACCESS (gpio_out=%h)", gpio_out);
      errors = errors + 1;
    end

    // Back-to-back APB write followed immediately by APB read (no idle cycle)
    @(negedge pclk);
    psel    = 1'b1;
    penable = 1'b0;
    pwrite  = 1'b1;
    paddr   = 6'h01; // 0x04
    pwdata  = 32'h0000_00C9;
    @(posedge pclk);
    @(negedge pclk);
    penable = 1'b1;
    @(posedge pclk);
    // Immediately start next SETUP for read
    @(negedge pclk);
    psel    = 1'b1;
    penable = 1'b0;
    pwrite  = 1'b0;
    paddr   = 6'h01; // 0x04
    @(posedge pclk);
    @(negedge pclk);
    penable = 1'b1;
    #(HALF_CLK - 1);
    if (prdata[7:0] !== 8'hC9) begin
      $display("FAIL: Back-to-back APB write->read expected 0xC9, got 0x%02h", prdata[7:0]);
      errors = errors + 1;
    end
    @(posedge pclk);
    @(negedge pclk);
    psel    = 1'b0;
    penable = 1'b0;
    paddr   = 6'h00;

    // -----------------------------------------------------------------------
    // TEST 4: Two-Stage Input Synchronizer Verification
    // -----------------------------------------------------------------------
    gpio_in = 8'h00;
    repeat (4) @(posedge pclk);
    check_reg(8'h00, 32'h0000_0000, 32'hFFFF_FFFF);

    // Change gpio_in and immediately start APB read of 0x00:
    // After 1 posedge, stage 1 has 0xA5, stage 2 must still have 0x00.
    @(negedge pclk);
    gpio_in = 8'hA5;
    psel    = 1'b1;
    penable = 1'b0;
    pwrite  = 1'b0;
    paddr   = 6'h00;
    @(posedge pclk); // sync1 <= A5, sync2 <= 00
    @(negedge pclk);
    penable = 1'b1;
    #(HALF_CLK - 1);
    if (prdata[7:0] !== 8'h00) begin
      $display("FAIL: Two-stage synchronizer bypassed! Expected 0x00 after 1 edge, got 0x%02h", prdata[7:0]);
      errors = errors + 1;
    end
    @(posedge pclk); // sync2 <= A5
    @(negedge pclk);
    psel    = 1'b0;
    penable = 1'b0;

    // Next read must reflect synchronized 0xA5
    check_reg(8'h00, 32'h0000_00A5, 32'h0000_00FF);

    gpio_in = 8'h5A;
    repeat (3) @(posedge pclk);
    check_reg(8'h00, 32'h0000_005A, 32'h0000_00FF);

    gpio_in = 8'h00;
    repeat (4) @(posedge pclk);

    // -----------------------------------------------------------------------
    // TEST 5: Interrupt Mode Discovery & Level / Edge / Polarity Verification
    // -----------------------------------------------------------------------
    cnt_lvl_hi = 0;
    cnt_lvl_lo = 0;
    cnt_edg_ri = 0;
    cnt_edg_fa = 0;

    for (t_idx = 0; t_idx < 2; t_idx = t_idx + 1) begin
      for (p_idx = 0; p_idx < 2; p_idx = p_idx + 1) begin
        apb_write(8'h0C, 32'h0);
        gpio_in = 8'h00;
        repeat (4) @(posedge pclk);

        apb_write(8'h10, {24'h0, {8{t_idx[0]}}});
        apb_write(8'h14, {24'h0, {8{p_idx[0]}}});
        apb_read(8'h18, rdata);

        // Even while gpio_in toggles, int_enable=0 must suppress all interrupts
        @(negedge pclk); gpio_in = 8'hFF;
        repeat (4) @(posedge pclk);
        if (gpio_int !== 8'h00 || comb_int !== 1'b0) begin
          $display("FAIL: Interrupt fired while int_enable=0 (t=%0d p=%0d int=%h)", t_idx, p_idx, gpio_int);
          errors = errors + 1;
        end
        @(negedge pclk); gpio_in = 8'h00;
        repeat (4) @(posedge pclk);

        // Enable pin 0
        apb_write(8'h0C, 32'h0000_0001);
        repeat (2) @(posedge pclk);
        #1;
        steady_low_init = gpio_int[0];

        // Rising edge on pin 0
        @(negedge pclk);
        gpio_in = 8'h01;
        saw_rise = 1'b0;
        for (k = 0; k < 6; k = k + 1) begin
          @(posedge pclk);
          #1;
          if (gpio_int[0] === 1'b1) saw_rise = 1'b1;
        end

        // Disable, clear COR if any, re-enable with gpio_in=1 steady
        apb_write(8'h0C, 32'h0);
        apb_read(8'h18, rdata);
        apb_write(8'h0C, 32'h0000_0001);
        repeat (3) @(posedge pclk);
        #1;
        steady_high_after = gpio_int[0];

        // Falling edge on pin 0
        @(negedge pclk);
        gpio_in = 8'h00;
        saw_fall = 1'b0;
        for (k = 0; k < 6; k = k + 1) begin
          @(posedge pclk);
          #1;
          if (gpio_int[0] === 1'b1) saw_fall = 1'b1;
        end

        // Disable, clear COR if any, re-enable with gpio_in=0 steady
        apb_write(8'h0C, 32'h0);
        apb_read(8'h18, rdata);
        apb_write(8'h0C, 32'h0000_0001);
        repeat (3) @(posedge pclk);
        #1;
        steady_low_after = gpio_int[0];

        apb_write(8'h0C, 32'h0);

        if (steady_high_after === 1'b1 && steady_low_after === 1'b0) begin
          cnt_lvl_hi = cnt_lvl_hi + 1;
          t_lvl_hi = t_idx[0];
          p_lvl_hi = p_idx[0];
        end else if (steady_low_after === 1'b1 && steady_high_after === 1'b0 && steady_low_init === 1'b1) begin
          cnt_lvl_lo = cnt_lvl_lo + 1;
          t_lvl_lo = t_idx[0];
          p_lvl_lo = p_idx[0];
        end else if (steady_high_after === 1'b0 && steady_low_after === 1'b0 && saw_rise === 1'b1 && saw_fall === 1'b0) begin
          cnt_edg_ri = cnt_edg_ri + 1;
          t_edg_ri = t_idx[0];
          p_edg_ri = p_idx[0];
        end else if (steady_high_after === 1'b0 && steady_low_after === 1'b0 && saw_rise === 1'b0 && saw_fall === 1'b1) begin
          cnt_edg_fa = cnt_edg_fa + 1;
          t_edg_fa = t_idx[0];
          p_edg_fa = p_idx[0];
        end else begin
          $display("FAIL: Ambiguous/broken interrupt behavior for type=%0d pol=%0d (s_lo_init=%b saw_r=%b s_hi_aft=%b saw_f=%b s_lo_aft=%b)",
                   t_idx, p_idx, steady_low_init, saw_rise, steady_high_after, saw_fall, steady_low_after);
          errors = errors + 1;
        end
      end
    end

    if (cnt_lvl_hi !== 1 || cnt_lvl_lo !== 1 || cnt_edg_ri !== 1 || cnt_edg_fa !== 1) begin
      $display("FAIL: Did not observe all 4 interrupt modes cleanly (lvl_hi=%0d lvl_lo=%0d edg_ri=%0d edg_fa=%0d)",
               cnt_lvl_hi, cnt_lvl_lo, cnt_edg_ri, cnt_edg_fa);
      errors = errors + 1;
    end else if (t_lvl_hi !== t_lvl_lo || t_edg_ri !== t_edg_fa || t_lvl_hi === t_edg_ri) begin
      $display("FAIL: Inconsistent interrupt type bit encoding across polarities");
      errors = errors + 1;
    end else begin
      t_level = t_lvl_hi;
      t_edge  = t_edg_ri;
      p_high  = p_lvl_hi;
      p_low   = p_lvl_lo;

      // Multi-pin Level-Sensitive Test: [3:0] active-high, [7:4] active-low
      gpio_in = 8'hF0; // inactive for all 8 pins
      repeat (4) @(posedge pclk);
      apb_write(8'h10, {24'h0, {8{t_level}}});
      apb_write(8'h14, {24'h0, {4{p_low}}, {4{p_high}}});
      apb_write(8'h0C, 32'h0000_00FF);
      repeat (3) @(posedge pclk);
      if (gpio_int !== 8'h00 || comb_int !== 1'b0) begin
        $display("FAIL: Multi-pin level inactive expected 0x00, got 0x%02h", gpio_int);
        errors = errors + 1;
      end
      check_reg(8'h18, 32'h0000_0000, 32'h0000_00FF);

      // Trigger upper nibble (active-low)
      @(negedge pclk); gpio_in = 8'h00;
      repeat (4) @(posedge pclk);
      if (gpio_int !== 8'hF0 || comb_int !== 1'b1) begin
        $display("FAIL: Multi-pin level upper nibble expected 0xF0, got 0x%02h", gpio_int);
        errors = errors + 1;
      end
      check_reg(8'h18, 32'h0000_00F0, 32'h0000_00FF);

      // Trigger lower nibble (active-high)
      @(negedge pclk); gpio_in = 8'hFF;
      repeat (4) @(posedge pclk);
      if (gpio_int !== 8'h0F || comb_int !== 1'b1) begin
        $display("FAIL: Multi-pin level lower nibble expected 0x0F, got 0x%02h", gpio_int);
        errors = errors + 1;
      end
      check_reg(8'h18, 32'h0000_000F, 32'h0000_00FF);

      // Simultaneous all 8 pins active
      @(negedge pclk); gpio_in = 8'h0F;
      repeat (4) @(posedge pclk);
      if (gpio_int !== 8'hFF || comb_int !== 1'b1) begin
        $display("FAIL: Multi-pin simultaneous level expected 0xFF, got 0x%02h", gpio_int);
        errors = errors + 1;
      end
      check_reg(8'h18, 32'h0000_00FF, 32'h0000_00FF);

      // Masking check via 0x0C
      apb_write(8'h0C, 32'h0000_0055);
      repeat (2) @(posedge pclk);
      if (gpio_int !== 8'h55 || comb_int !== 1'b1) begin
        $display("FAIL: Masked level interrupt expected 0x55, got 0x%02h", gpio_int);
        errors = errors + 1;
      end
      check_reg(8'h18, 32'h0000_0055, 32'h0000_00FF);

      // Multi-pin Edge-Sensitive Test: [3:0] rising-edge, [7:4] falling-edge
      apb_write(8'h0C, 32'h0000_0000);
      @(negedge pclk); gpio_in = 8'hF0;
      repeat (4) @(posedge pclk);
      apb_write(8'h10, {24'h0, {8{t_edge}}});
      apb_write(8'h14, {24'h0, {4{p_edg_fa}}, {4{p_edg_ri}}});
      apb_read(8'h18, rdata);
      apb_write(8'h0C, 32'h0000_00FF);
      repeat (2) @(posedge pclk);

      // Active edge on all 8 pins simultaneously: 8'hF0 -> 8'h0F
      @(negedge pclk); gpio_in = 8'h0F;
      seen_edge_int = 8'h00;
      for (k = 0; k < 6; k = k + 1) begin
        @(posedge pclk);
        #1;
        seen_edge_int = seen_edge_int | gpio_int;
      end
      if (seen_edge_int !== 8'hFF) begin
        $display("FAIL: Simultaneous edge-sensitive interrupts expected 0xFF, saw 0x%02h", seen_edge_int);
        errors = errors + 1;
      end

      // Clear any latched edge interrupt and verify opposite edge does NOT fire
      apb_write(8'h0C, 32'h0000_0000);
      apb_read(8'h18, rdata);
      apb_write(8'h0C, 32'h0000_00FF);
      repeat (2) @(posedge pclk);

      @(negedge pclk); gpio_in = 8'hF0;
      seen_edge_int = 8'h00;
      for (k = 0; k < 6; k = k + 1) begin
        @(posedge pclk);
        #1;
        seen_edge_int = seen_edge_int | gpio_int;
      end
      if (seen_edge_int !== 8'h00) begin
        $display("FAIL: Opposite edge triggered interrupts unexpectedly (saw 0x%02h)", seen_edge_int);
        errors = errors + 1;
      end
    end

    // -----------------------------------------------------------------------
    // TEST 6: Mid-Operation Asynchronous Reset
    // -----------------------------------------------------------------------
    apb_write(8'h04, 32'h0000_00AA);
    apb_write(8'h08, 32'h0000_0055);
    apb_write(8'h10, {24'h0, {8{t_level}}});
    apb_write(8'h14, {24'h0, {8{p_high}}});
    apb_write(8'h0C, 32'h0000_00FF);
    @(negedge pclk); gpio_in = 8'hFF;
    repeat (4) @(posedge pclk);

    if (gpio_out !== 8'hAA || gpio_enable !== 8'h55 || gpio_int !== 8'hFF || comb_int !== 1'b1) begin
      $display("FAIL: Pre-reset active state mismatch (out=%h en=%h int=%h comb=%b)",
               gpio_out, gpio_enable, gpio_int, comb_int);
      errors = errors + 1;
    end

    // Assert preset_n asynchronously mid-cycle (before posedge)
    @(negedge pclk);
    #2;
    preset_n = 1'b0;
    #1;
    if (gpio_out !== 8'h00 || gpio_enable !== 8'h00 || gpio_int !== 8'h00 ||
        comb_int !== 1'b0 || pslverr !== 1'b0) begin
      $display("FAIL: Mid-op async reset did not clear outputs immediately (out=%h en=%h int=%h comb=%b)",
               gpio_out, gpio_enable, gpio_int, comb_int);
      errors = errors + 1;
    end

    gpio_in = 8'h00;
    repeat (2) @(posedge pclk);
    @(negedge pclk);
    preset_n = 1'b1;
    @(posedge pclk);

    check_reg(8'h00, 32'h0, 32'hFFFF_FFFF);
    check_reg(8'h04, 32'h0, 32'hFFFF_FFFF);
    check_reg(8'h08, 32'h0, 32'hFFFF_FFFF);
    check_reg(8'h0C, 32'h0, 32'hFFFF_FFFF);
    check_reg(8'h10, 32'h0, 32'hFFFF_FFFF);
    check_reg(8'h14, 32'h0, 32'hFFFF_FFFF);
    check_reg(8'h18, 32'h0, 32'hFFFF_FFFF);

    // -----------------------------------------------------------------------
    // TEST 7: Parameterized Width Verification (GPIO_WIDTH = 16)
    // -----------------------------------------------------------------------
    apb16_write(8'h04, 32'h0000_A55A);
    apb16_write(8'h08, 32'h0000_F00F);
    if (gpio_out16 !== 16'hA55A) begin
      $display("FAIL: dut16 gpio_out16 expected 0xA55A, got 0x%04h", gpio_out16);
      errors = errors + 1;
    end
    if (gpio_enable16 !== 16'hF00F) begin
      $display("FAIL: dut16 gpio_enable16 expected 0xF00F, got 0x%04h", gpio_enable16);
      errors = errors + 1;
    end
    apb16_read(8'h04, rdata);
    if (rdata[15:0] !== 16'hA55A) begin
      $display("FAIL: dut16 reg 0x04 expected 0xA55A, got 0x%04h", rdata[15:0]);
      errors = errors + 1;
    end

    @(negedge pclk); gpio_in16 = 16'hC33C;
    repeat (4) @(posedge pclk);
    apb16_read(8'h00, rdata);
    if (rdata[15:0] !== 16'hC33C) begin
      $display("FAIL: dut16 reg 0x00 expected 0xC33C, got 0x%04h", rdata[15:0]);
      errors = errors + 1;
    end

    apb16_write(8'h10, {16'h0, {16{t_level}}});
    apb16_write(8'h14, {16'h0, {16{p_high}}});
    apb16_write(8'h0C, 32'h0000_FFFF);
    repeat (3) @(posedge pclk);
    if (gpio_int16 !== 16'hC33C || comb_int16 !== 1'b1) begin
      $display("FAIL: dut16 gpio_int16 expected 0xC33C, got 0x%04h (comb=%b)", gpio_int16, comb_int16);
      errors = errors + 1;
    end
    apb16_read(8'h18, rdata);
    if (rdata[15:0] !== 16'hC33C) begin
      $display("FAIL: dut16 reg 0x18 expected 0xC33C, got 0x%04h", rdata[15:0]);
      errors = errors + 1;
    end

    // Test MSB (pin 15) independently
    @(negedge pclk); gpio_in16 = 16'h8000;
    repeat (4) @(posedge pclk);
    if (gpio_int16 !== 16'h8000 || comb_int16 !== 1'b1) begin
      $display("FAIL: dut16 MSB interrupt expected 0x8000, got 0x%04h", gpio_int16);
      errors = errors + 1;
    end

    // -----------------------------------------------------------------------
    // Final Summary
    // -----------------------------------------------------------------------
    if (errors == 0) begin
      $display("PASS");
    end else begin
      $display("FAIL: %0d errors", errors);
    end
    $finish;
  end

endmodule
