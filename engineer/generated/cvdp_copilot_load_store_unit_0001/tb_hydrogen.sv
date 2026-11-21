`timescale 1ns/1ps

module tb;
  // Clock and Reset
  logic        clk;
  logic        rst_n;

  // Data-Cache Interface
  logic        dmem_req_o;
  logic        dmem_gnt_i;
  logic [31:0] dmem_req_addr_o;
  logic        dmem_req_we_o;
  logic [3:0]  dmem_req_be_o;
  logic [31:0] dmem_req_wdata_o;
  logic        dmem_rvalid_i;
  logic [31:0] dmem_rsp_rdata_i;

  // Execution Stage Interface
  logic        ex_if_req_i;
  logic        ex_if_we_i;
  logic [1:0]  ex_if_type_i;
  logic [31:0] ex_if_wdata_i;
  logic [31:0] ex_if_addr_base_i;
  logic [31:0] ex_if_addr_offset_i;
  logic        ex_if_ready_o;

  // Writeback Interface
  logic [31:0] wb_if_rdata_o;
  logic        wb_if_rvalid_o;

  // Testbench state
  integer      errors = 0;
  logic [31:0] last_wb_rdata;
  integer      seed = 32'h1357_2468;
  integer      t_idx;

  // DUT Instantiation
  load_store_unit dut (
    .clk                 (clk),
    .rst_n               (rst_n),
    .dmem_req_o          (dmem_req_o),
    .dmem_gnt_i          (dmem_gnt_i),
    .dmem_req_addr_o     (dmem_req_addr_o),
    .dmem_req_we_o       (dmem_req_we_o),
    .dmem_req_be_o       (dmem_req_be_o),
    .dmem_req_wdata_o    (dmem_req_wdata_o),
    .dmem_rvalid_i       (dmem_rvalid_i),
    .dmem_rsp_rdata_i    (dmem_rsp_rdata_i),
    .ex_if_req_i         (ex_if_req_i),
    .ex_if_we_i          (ex_if_we_i),
    .ex_if_type_i        (ex_if_type_i),
    .ex_if_wdata_i       (ex_if_wdata_i),
    .ex_if_addr_base_i   (ex_if_addr_base_i),
    .ex_if_addr_offset_i (ex_if_addr_offset_i),
    .ex_if_ready_o       (ex_if_ready_o),
    .wb_if_rdata_o       (wb_if_rdata_o),
    .wb_if_rvalid_o      (wb_if_rvalid_o)
  );

  // Clock generation: 10ns period
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // Watchdog timeout
  initial begin
    repeat (5000) @(posedge clk);
    $display("FAIL: Watchdog timeout reached");
    errors = errors + 1;
    $display("FAIL: %0d errors", errors);
    $finish;
  end

  // Helper task to clear all driven inputs
  task clear_inputs;
    begin
      ex_if_req_i         = 1'b0;
      ex_if_we_i          = 1'b0;
      ex_if_type_i        = 2'b00;
      ex_if_wdata_i       = 32'h0;
      ex_if_addr_base_i   = 32'h0;
      ex_if_addr_offset_i = 32'h0;
      dmem_gnt_i          = 1'b0;
      dmem_rvalid_i       = 1'b0;
      dmem_rsp_rdata_i    = 32'h0;
    end
  endtask

  // Check reset defaults
  task check_reset_outputs;
    input [8*32-1:0] ctx;
    begin
      if (ex_if_ready_o !== 1'b1) begin
        $display("FAIL: [%0s] reset ex_if_ready_o expected 1, got %b", ctx, ex_if_ready_o);
        errors = errors + 1;
      end
      if (dmem_req_o !== 1'b0) begin
        $display("FAIL: [%0s] reset dmem_req_o expected 0, got %b", ctx, dmem_req_o);
        errors = errors + 1;
      end
      if (dmem_req_we_o !== 1'b0) begin
        $display("FAIL: [%0s] reset dmem_req_we_o expected 0, got %b", ctx, dmem_req_we_o);
        errors = errors + 1;
      end
      if (dmem_req_addr_o !== 32'h0) begin
        $display("FAIL: [%0s] reset dmem_req_addr_o expected 0x00000000, got 0x%08h", ctx, dmem_req_addr_o);
        errors = errors + 1;
      end
      if (dmem_req_be_o !== 4'h0) begin
        $display("FAIL: [%0s] reset dmem_req_be_o expected 0x0, got 0x%0h", ctx, dmem_req_be_o);
        errors = errors + 1;
      end
      if (dmem_req_wdata_o !== 32'h0) begin
        $display("FAIL: [%0s] reset dmem_req_wdata_o expected 0x00000000, got 0x%08h", ctx, dmem_req_wdata_o);
        errors = errors + 1;
      end
      if (wb_if_rvalid_o !== 1'b0) begin
        $display("FAIL: [%0s] reset wb_if_rvalid_o expected 0, got %b", ctx, wb_if_rvalid_o);
        errors = errors + 1;
      end
      if (wb_if_rdata_o !== 32'h0) begin
        $display("FAIL: [%0s] reset wb_if_rdata_o expected 0x00000000, got 0x%08h", ctx, wb_if_rdata_o);
        errors = errors + 1;
      end
    end
  endtask

  // Check post-grant cleared dmem request outputs
  task check_dmem_cleared;
    input [8*32-1:0] ctx;
    begin
      if (dmem_req_o !== 1'b0) begin
        $display("FAIL: [%0s] post-grant dmem_req_o expected 0, got %b", ctx, dmem_req_o);
        errors = errors + 1;
      end
      if (dmem_req_we_o !== 1'b0) begin
        $display("FAIL: [%0s] post-grant dmem_req_we_o expected 0, got %b", ctx, dmem_req_we_o);
        errors = errors + 1;
      end
      if (dmem_req_addr_o !== 32'h0) begin
        $display("FAIL: [%0s] post-grant dmem_req_addr_o expected 0x00000000, got 0x%08h", ctx, dmem_req_addr_o);
        errors = errors + 1;
      end
      if (dmem_req_be_o !== 4'h0) begin
        $display("FAIL: [%0s] post-grant dmem_req_be_o expected 0x0, got 0x%0h", ctx, dmem_req_be_o);
        errors = errors + 1;
      end
      if (dmem_req_wdata_o !== 32'h0) begin
        $display("FAIL: [%0s] post-grant dmem_req_wdata_o expected 0x00000000, got 0x%08h", ctx, dmem_req_wdata_o);
        errors = errors + 1;
      end
    end
  endtask

  // Execute one full LSU transaction (must enter and exit at negedge clk)
  task run_txn;
    input        we;
    input [1:0]  typ;
    input [31:0] base;
    input [31:0] offset;
    input [31:0] wdata;
    input [31:0] rdata;
    input integer gnt_delay;     // >= 0 cycles after req rises
    input integer rvalid_delay;  // >= 1 cycles after grant is sampled
    input        check_wb_end;   // 1 = wait extra cycle to verify 1-cycle wb_if_rvalid_o pulse

    logic [31:0] exp_addr;
    logic [1:0]  lsb;
    logic        exp_valid;
    logic [3:0]  exp_be;
    integer      i;
    begin
      exp_addr = base + offset;
      lsb      = exp_addr[1:0];

      case (typ)
        2'b00: begin
          exp_valid = 1'b1;
          exp_be    = (4'b0001 << lsb);
        end
        2'b01: begin
          exp_valid = (lsb[0] == 1'b0);
          exp_be    = (lsb[1] == 1'b1) ? 4'b1100 : 4'b0011;
        end
        2'b10: begin
          exp_valid = (lsb == 2'b00);
          exp_be    = 4'b1111;
        end
        default: begin
          exp_valid = 1'b0;
          exp_be    = 4'b0000;
        end
      endcase

      if (ex_if_ready_o !== 1'b1) begin
        $display("FAIL: [txn] expected ex_if_ready_o == 1 before request, got %b", ex_if_ready_o);
        errors = errors + 1;
      end

      // Drive EX request at negedge
      ex_if_req_i         = 1'b1;
      ex_if_we_i          = we;
      ex_if_type_i        = typ;
      ex_if_wdata_i       = wdata;
      ex_if_addr_base_i   = base;
      ex_if_addr_offset_i = offset;

      // Posedge #1: DUT samples EX request
      @(posedge clk);
      #1;

      if (!exp_valid) begin
        // Misaligned or invalid type must be discarded
        if (ex_if_ready_o !== 1'b1) begin
          $display("FAIL: [misaligned] ex_if_ready_o expected 1, got %b (addr=0x%08h type=%b)", ex_if_ready_o, exp_addr, typ);
          errors = errors + 1;
        end
        check_dmem_cleared("misaligned");
        if (wb_if_rvalid_o !== 1'b0) begin
          $display("FAIL: [misaligned] wb_if_rvalid_o expected 0, got %b", wb_if_rvalid_o);
          errors = errors + 1;
        end
        if (wb_if_rdata_o !== last_wb_rdata) begin
          $display("FAIL: [misaligned] wb_if_rdata_o expected 0x%08h, got 0x%08h", last_wb_rdata, wb_if_rdata_o);
          errors = errors + 1;
        end

        @(negedge clk);
        ex_if_req_i         = 1'b0;
        ex_if_we_i          = 1'b0;
        ex_if_type_i        = 2'b00;
        ex_if_wdata_i       = 32'h0;
        ex_if_addr_base_i   = 32'h0;
        ex_if_addr_offset_i = 32'h0;

        if (check_wb_end) begin
          @(posedge clk);
          #1;
          check_dmem_cleared("misaligned_idle");
          if (ex_if_ready_o !== 1'b1) begin
            $display("FAIL: [misaligned_idle] ex_if_ready_o expected 1, got %b", ex_if_ready_o);
            errors = errors + 1;
          end
          @(negedge clk);
        end
      end else begin
        // Valid aligned request accepted
        if (ex_if_ready_o !== 1'b0) begin
          $display("FAIL: [req] ex_if_ready_o expected 0 after accept, got %b", ex_if_ready_o);
          errors = errors + 1;
        end
        if (dmem_req_o !== 1'b1) begin
          $display("FAIL: [req] dmem_req_o expected 1, got %b", dmem_req_o);
          errors = errors + 1;
        end
        if (dmem_req_addr_o !== exp_addr) begin
          $display("FAIL: [req] dmem_req_addr_o expected 0x%08h, got 0x%08h", exp_addr, dmem_req_addr_o);
          errors = errors + 1;
        end
        if (dmem_req_we_o !== we) begin
          $display("FAIL: [req] dmem_req_we_o expected %b, got %b", we, dmem_req_we_o);
          errors = errors + 1;
        end
        if (dmem_req_be_o !== exp_be) begin
          $display("FAIL: [req] dmem_req_be_o expected 0x%0h, got 0x%0h (addr=0x%08h type=%b)", exp_be, dmem_req_be_o, exp_addr, typ);
          errors = errors + 1;
        end
        if (we && (dmem_req_wdata_o !== wdata)) begin
          $display("FAIL: [req] dmem_req_wdata_o expected 0x%08h, got 0x%08h", wdata, dmem_req_wdata_o);
          errors = errors + 1;
        end
        if (wb_if_rvalid_o !== 1'b0) begin
          $display("FAIL: [req] wb_if_rvalid_o expected 0, got %b", wb_if_rvalid_o);
          errors = errors + 1;
        end
        if (wb_if_rdata_o !== last_wb_rdata) begin
          $display("FAIL: [req] wb_if_rdata_o expected 0x%08h, got 0x%08h", last_wb_rdata, wb_if_rdata_o);
          errors = errors + 1;
        end

        // Deassert and scramble EX inputs to ensure DUT registered request info
        @(negedge clk);
        ex_if_req_i         = 1'b0;
        ex_if_we_i          = ~we;
        ex_if_type_i        = typ ^ 2'b11;
        ex_if_wdata_i       = ~wdata;
        ex_if_addr_base_i   = ~base;
        ex_if_addr_offset_i = 32'h0000_0003;

        // Wait cycles before grant
        for (i = 0; i < gnt_delay; i = i + 1) begin
          @(posedge clk);
          #1;
          if (dmem_req_o !== 1'b1) begin
            $display("FAIL: [gnt_wait] dmem_req_o expected 1, got %b", dmem_req_o);
            errors = errors + 1;
          end
          if (dmem_req_addr_o !== exp_addr) begin
            $display("FAIL: [gnt_wait] dmem_req_addr_o changed to 0x%08h, expected 0x%08h", dmem_req_addr_o, exp_addr);
            errors = errors + 1;
          end
          if (dmem_req_we_o !== we) begin
            $display("FAIL: [gnt_wait] dmem_req_we_o changed to %b, expected %b", dmem_req_we_o, we);
            errors = errors + 1;
          end
          if (dmem_req_be_o !== exp_be) begin
            $display("FAIL: [gnt_wait] dmem_req_be_o changed to 0x%0h, expected 0x%0h", dmem_req_be_o, exp_be);
            errors = errors + 1;
          end
          if (we && (dmem_req_wdata_o !== wdata)) begin
            $display("FAIL: [gnt_wait] dmem_req_wdata_o changed to 0x%08h, expected 0x%08h", dmem_req_wdata_o, wdata);
            errors = errors + 1;
          end
          if (ex_if_ready_o !== 1'b0) begin
            $display("FAIL: [gnt_wait] ex_if_ready_o expected 0, got %b", ex_if_ready_o);
            errors = errors + 1;
          end
          if (wb_if_rvalid_o !== 1'b0) begin
            $display("FAIL: [gnt_wait] wb_if_rvalid_o expected 0, got %b", wb_if_rvalid_o);
            errors = errors + 1;
          end
          @(negedge clk);
        end

        // Assert grant before next posedge
        dmem_gnt_i = 1'b1;
        @(posedge clk);
        #1;

        // Post-grant checks
        check_dmem_cleared("post_grant");
        if (wb_if_rvalid_o !== 1'b0) begin
          $display("FAIL: [post_grant] wb_if_rvalid_o expected 0, got %b", wb_if_rvalid_o);
          errors = errors + 1;
        end
        if (wb_if_rdata_o !== last_wb_rdata) begin
          $display("FAIL: [post_grant] wb_if_rdata_o expected 0x%08h, got 0x%08h", last_wb_rdata, wb_if_rdata_o);
          errors = errors + 1;
        end

        if (we) begin
          // Store completes on grant -> ex_if_ready_o asserts with 1-cycle latency
          if (ex_if_ready_o !== 1'b1) begin
            $display("FAIL: [store_done] ex_if_ready_o expected 1, got %b", ex_if_ready_o);
            errors = errors + 1;
          end
          @(negedge clk);
          dmem_gnt_i = 1'b0;
        end else begin
          // Load still waiting for dmem_rvalid_i -> ex_if_ready_o remains 0
          if (ex_if_ready_o !== 1'b0) begin
            $display("FAIL: [load_gnt] ex_if_ready_o expected 0 while waiting rvalid, got %b", ex_if_ready_o);
            errors = errors + 1;
          end
          @(negedge clk);
          dmem_gnt_i = 1'b0;

          // Wait cycles before dmem_rvalid_i (rvalid_delay >= 1)
          for (i = 1; i < rvalid_delay; i = i + 1) begin
            @(posedge clk);
            #1;
            check_dmem_cleared("load_rvalid_wait");
            if (ex_if_ready_o !== 1'b0) begin
              $display("FAIL: [load_rvalid_wait] ex_if_ready_o expected 0, got %b", ex_if_ready_o);
              errors = errors + 1;
            end
            if (wb_if_rvalid_o !== 1'b0) begin
              $display("FAIL: [load_rvalid_wait] wb_if_rvalid_o expected 0, got %b", wb_if_rvalid_o);
              errors = errors + 1;
            end
            if (wb_if_rdata_o !== last_wb_rdata) begin
              $display("FAIL: [load_rvalid_wait] wb_if_rdata_o expected 0x%08h, got 0x%08h", last_wb_rdata, wb_if_rdata_o);
              errors = errors + 1;
            end
            @(negedge clk);
          end

          // Drive dmem_rvalid_i for 1 cycle
          dmem_rvalid_i    = 1'b1;
          dmem_rsp_rdata_i = rdata;
          @(posedge clk);
          #1;

          // Load response appears at WB and ex_if_ready_o reasserts (1-cycle latency)
          if (wb_if_rvalid_o !== 1'b1) begin
            $display("FAIL: [load_wb] wb_if_rvalid_o expected 1, got %b", wb_if_rvalid_o);
            errors = errors + 1;
          end
          if (wb_if_rdata_o !== rdata) begin
            $display("FAIL: [load_wb] wb_if_rdata_o expected 0x%08h, got 0x%08h", rdata, wb_if_rdata_o);
            errors = errors + 1;
          end
          if (ex_if_ready_o !== 1'b1) begin
            $display("FAIL: [load_wb] ex_if_ready_o expected 1, got %b", ex_if_ready_o);
            errors = errors + 1;
          end
          check_dmem_cleared("load_wb");

          last_wb_rdata = rdata;

          @(negedge clk);
          dmem_rvalid_i    = 1'b0;
          dmem_rsp_rdata_i = ~rdata;

          if (check_wb_end) begin
            @(posedge clk);
            #1;
            if (wb_if_rvalid_o !== 1'b0) begin
              $display("FAIL: [load_wb_end] wb_if_rvalid_o expected 0 after 1 cycle, got %b", wb_if_rvalid_o);
              errors = errors + 1;
            end
            if (wb_if_rdata_o !== last_wb_rdata) begin
              $display("FAIL: [load_wb_end] wb_if_rdata_o not retained: expected 0x%08h, got 0x%08h", last_wb_rdata, wb_if_rdata_o);
              errors = errors + 1;
            end
            if (ex_if_ready_o !== 1'b1) begin
              $display("FAIL: [load_wb_end] ex_if_ready_o expected 1, got %b", ex_if_ready_o);
              errors = errors + 1;
            end
            @(negedge clk);
          end
        end
      end
    end
  endtask

  // Main test sequence
  initial begin
    clear_inputs;
    last_wb_rdata = 32'h0;
    rst_n = 1'b0;

    // ---------------------------------------------------------
    // 1. Asynchronous and synchronous reset behavior
    // ---------------------------------------------------------
    #1;
    check_reset_outputs("async_reset_init");

    repeat (3) begin
      @(posedge clk);
      #1;
      check_reset_outputs("reset_held");
    end

    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    check_reset_outputs("post_reset_idle");

    // ---------------------------------------------------------
    // 2. Idle check: ex_if_req_i = 0 with ex_if_we_i = 1
    // ---------------------------------------------------------
    @(negedge clk);
    ex_if_req_i         = 1'b0;
    ex_if_we_i          = 1'b1;
    ex_if_type_i        = 2'b10;
    ex_if_wdata_i       = 32'hCAFE_BABE;
    ex_if_addr_base_i   = 32'h0000_1000;
    ex_if_addr_offset_i = 32'h0000_0004;
    repeat (2) begin
      @(posedge clk);
      #1;
      check_reset_outputs("idle_no_req");
    end
    @(negedge clk);
    clear_inputs;

    // ---------------------------------------------------------
    // 3. WaveDrom example: Store word -> Load byte back-to-back
    // ---------------------------------------------------------
    run_txn(1'b1, 2'b10, 32'h0000_0004, 32'h0000_0000, 32'hDEAD_BEEF, 32'h0,        3, 1, 1'b0);
    run_txn(1'b0, 2'b00, 32'h0000_0004, 32'h0000_0000, 32'h0,         32'h0000_00EF, 2, 1, 1'b1);

    // ---------------------------------------------------------
    // 4. All byte lanes (00, 01, 10, 11) - Stores and Loads
    // ---------------------------------------------------------
    run_txn(1'b1, 2'b00, 32'h1000_0000, 32'h0000_0000, 32'h1122_3344, 32'h0,        0, 1, 1'b1);
    run_txn(1'b1, 2'b00, 32'h1000_0000, 32'h0000_0001, 32'h5566_7788, 32'h0,        1, 1, 1'b1);
    run_txn(1'b1, 2'b00, 32'h1000_0000, 32'h0000_0002, 32'h99AA_BBCC, 32'h0,        2, 1, 1'b1);
    run_txn(1'b1, 2'b00, 32'h1000_0000, 32'h0000_0003, 32'hDDEE_FF00, 32'h0,        0, 1, 1'b1);

    run_txn(1'b0, 2'b00, 32'h1000_0000, 32'h0000_0000, 32'h0,         32'h0000_0044, 0, 1, 1'b1);
    run_txn(1'b0, 2'b00, 32'h1000_0000, 32'h0000_0001, 32'h0,         32'h0000_7700, 1, 2, 1'b1);
    run_txn(1'b0, 2'b00, 32'h1000_0000, 32'h0000_0002, 32'h0,         32'h00BB_0000, 0, 3, 1'b1);
    run_txn(1'b0, 2'b00, 32'h1000_0000, 32'h0000_0003, 32'h0,         32'hDD00_0000, 2, 4, 1'b1);

    // ---------------------------------------------------------
    // 5. Halfword aligned accesses (addr[1:0] = 00 and 10)
    // ---------------------------------------------------------
    run_txn(1'b1, 2'b01, 32'h2000_0000, 32'h0000_0000, 32'h1234_5678, 32'h0,        0, 1, 1'b1);
    run_txn(1'b1, 2'b01, 32'h2000_0000, 32'h0000_0002, 32'hABCD_EF01, 32'h0,        2, 1, 1'b1);
    run_txn(1'b0, 2'b01, 32'h2000_0001, 32'h0000_0001, 32'h0,         32'hABCD_0000, 0, 2, 1'b1); // 1+1=2 (aligned!)
    run_txn(1'b0, 2'b01, 32'h2000_0003, 32'h0000_0001, 32'h0,         32'h0000_5678, 1, 1, 1'b1); // 3+1=4 (aligned!)

    // ---------------------------------------------------------
    // 6. Word accesses & address arithmetic (negative offset, wrap)
    // ---------------------------------------------------------
    run_txn(1'b1, 2'b10, 32'h3000_0008, 32'hFFFF_FFFC, 32'hA5A5_5A5A, 32'h0,        1, 1, 1'b1); // -4 -> 0x3000_0004
    run_txn(1'b0, 2'b10, 32'hFFFF_FFFC, 32'h0000_0008, 32'h0,         32'hCAFE_F00D, 0, 1, 1'b1); // wrap -> 0x0000_0004
    run_txn(1'b1, 2'b10, 32'hFFFF_FFF0, 32'h0000_000C, 32'hDEAD_C0DE, 32'h0,        0, 1, 1'b1); // 0xFFFF_FFFC

    // Verify wb_if_rdata_o retained 0xCAFE_F00D across the previous store!
    if (wb_if_rdata_o !== 32'hCAFE_F00D) begin
      $display("FAIL: [retain_across_store] wb_if_rdata_o expected 0xCAFEF00D, got 0x%08h", wb_if_rdata_o);
      errors = errors + 1;
    end

    // ---------------------------------------------------------
    // 7. Misaligned accesses and invalid type 2'b11 (must be discarded)
    // ---------------------------------------------------------
    // Halfword misaligned: 01 and 11
    run_txn(1'b1, 2'b01, 32'h4000_0000, 32'h0000_0001, 32'h1111_1111, 32'h0, 0, 1, 1'b1);
    run_txn(1'b0, 2'b01, 32'h4000_0000, 32'h0000_0003, 32'h0,         32'h1, 0, 1, 1'b1);
    // Word misaligned: 01, 10, 11
    run_txn(1'b1, 2'b10, 32'h4000_0000, 32'h0000_0001, 32'h2222_2222, 32'h0, 0, 1, 1'b1);
    run_txn(1'b0, 2'b10, 32'h4000_0000, 32'h0000_0002, 32'h0,         32'h2, 0, 1, 1'b1);
    run_txn(1'b1, 2'b10, 32'h4000_0003, 32'h0000_0000, 32'h3333_3333, 32'h0, 0, 1, 1'b1);
    // Invalid type 2'b11 (aligned and unaligned)
    run_txn(1'b1, 2'b11, 32'h4000_0000, 32'h0000_0000, 32'h4444_4444, 32'h0, 0, 1, 1'b1);
    run_txn(1'b0, 2'b11, 32'h4000_0000, 32'h0000_0001, 32'h0,         32'h4, 0, 1, 1'b1);

    // ---------------------------------------------------------
    // 8. Back-to-back stress: Store->Store, Load->Load, Load->Store, Misaligned->Valid
    // ---------------------------------------------------------
    run_txn(1'b1, 2'b10, 32'h5000_0000, 32'h0, 32'h0102_0304, 32'h0,         0, 1, 1'b0);
    run_txn(1'b1, 2'b10, 32'h5000_0004, 32'h0, 32'h0506_0708, 32'h0,         1, 1, 1'b0);
    run_txn(1'b0, 2'b10, 32'h5000_0000, 32'h0, 32'h0,         32'h0102_0304, 0, 1, 1'b0);
    run_txn(1'b0, 2'b10, 32'h5000_0004, 32'h0, 32'h0,         32'h0506_0708, 2, 2, 1'b0);
    run_txn(1'b1, 2'b10, 32'h5000_0008, 32'h0, 32'h090A_0B0C, 32'h0,         0, 1, 1'b0);
    run_txn(1'b0, 2'b10, 32'h5000_0001, 32'h0, 32'h0,         32'h0,         0, 1, 1'b0); // misaligned
    run_txn(1'b0, 2'b10, 32'h5000_0008, 32'h0, 32'h0,         32'h090A_0B0C, 0, 1, 1'b1);

    // ---------------------------------------------------------
    // 9. Asynchronous reset mid-transaction
    // ---------------------------------------------------------
    // 9a. Reset while store is waiting for grant
    ex_if_req_i         = 1'b1;
    ex_if_we_i          = 1'b1;
    ex_if_type_i        = 2'b10;
    ex_if_wdata_i       = 32'hDEAD_BEEF;
    ex_if_addr_base_i   = 32'h6000_0000;
    ex_if_addr_offset_i = 32'h0;
    @(posedge clk);
    #1;
    if (dmem_req_o !== 1'b1 || ex_if_ready_o !== 1'b0) begin
      $display("FAIL: [mid_rst_store] expected active req before reset");
      errors = errors + 1;
    end
    #2; // asynchronous between clock edges
    rst_n = 1'b0;
    #1;
    check_reset_outputs("async_rst_during_store_req");
    @(negedge clk);
    clear_inputs;
    @(posedge clk);
    #1;
    check_reset_outputs("async_rst_store_settled");
    @(negedge clk);
    rst_n = 1'b1;
    last_wb_rdata = 32'h0;
    @(posedge clk);
    #1;

    // 9b. Reset while load is granted and waiting for dmem_rvalid_i
    @(negedge clk);
    ex_if_req_i         = 1'b1;
    ex_if_we_i          = 1'b0;
    ex_if_type_i        = 2'b10;
    ex_if_addr_base_i   = 32'h7000_0000;
    ex_if_addr_offset_i = 32'h0;
    @(posedge clk);
    #1;
    @(negedge clk);
    ex_if_req_i = 1'b0;
    dmem_gnt_i  = 1'b1;
    @(posedge clk);
    #1;
    if (ex_if_ready_o !== 1'b0 || dmem_req_o !== 1'b0) begin
      $display("FAIL: [mid_rst_load] expected granted load waiting for rvalid");
      errors = errors + 1;
    end
    @(negedge clk);
    dmem_gnt_i = 1'b0;
    #2; // asynchronous mid-cycle reset
    rst_n = 1'b0;
    #1;
    check_reset_outputs("async_rst_during_load_wait");
    @(posedge clk);
    #1;
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    @(negedge clk);

    // Ensure LSU works cleanly after mid-transaction resets
    run_txn(1'b0, 2'b10, 32'h8000_0000, 32'h0, 32'h0, 32'h1357_9BDF, 1, 2, 1'b1);

    // ---------------------------------------------------------
    // 10. Randomized stress test
    // ---------------------------------------------------------
    for (t_idx = 0; t_idx < 40; t_idx = t_idx + 1) begin
      logic        r_we;
      logic [1:0]  r_typ;
      logic [31:0] r_base, r_off, r_wdata, r_rdata;
      integer      r_gnt_dly, r_rv_dly, r_idle;
      logic        r_b2b;

      r_we      = $random(seed) & 1'b1;
      r_typ     = $random(seed) & 2'b11;
      r_base    = $random(seed);
      r_off     = $random(seed);
      r_wdata   = $random(seed);
      r_rdata   = $random(seed);
      r_gnt_dly = ($random(seed) & 32'h3);
      r_rv_dly  = 1 + ($random(seed) & 32'h3);
      r_idle    = ($random(seed) & 32'h3);
      r_b2b     = (r_idle == 0);

      run_txn(r_we, r_typ, r_base, r_off, r_wdata, r_rdata, r_gnt_dly, r_rv_dly, !r_b2b);

      if (!r_b2b && r_idle > 1) begin
        repeat (r_idle - 1) begin
          @(posedge clk);
          #1;
          check_dmem_cleared("rand_idle");
          if (ex_if_ready_o !== 1'b1) begin
            $display("FAIL: [rand_idle] ex_if_ready_o expected 1, got %b", ex_if_ready_o);
            errors = errors + 1;
          end
          if (wb_if_rvalid_o !== 1'b0) begin
            $display("FAIL: [rand_idle] wb_if_rvalid_o expected 0, got %b", wb_if_rvalid_o);
            errors = errors + 1;
          end
          @(negedge clk);
        end
      end
    end

    // Final settle cycle
    @(posedge clk);
    #1;

    if (errors == 0) begin
      $display("PASS");
    end else begin
      $display("FAIL: %0d errors", errors);
    end
    $finish;
  end
endmodule
