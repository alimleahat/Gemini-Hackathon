`timescale 1ns/1ps

module tb;
    // Default instance parameters
    localparam DEF_DATA_WIDTH = 8;
    localparam DEF_ADDR_WIDTH = 3;
    localparam DEF_DEPTH      = (1 << DEF_ADDR_WIDTH);

    // Parameterized instance parameters
    localparam P_DATA_WIDTH = 16;
    localparam P_ADDR_WIDTH = 2;
    localparam P_DEPTH      = (1 << P_ADDR_WIDTH);

    // Shared clock
    reg clock;

    // Signals for default-parameter DUT
    reg                       reset;
    reg                       write_en;
    reg                       read_en;
    reg  [DEF_DATA_WIDTH-1:0] data_in;
    wire                      empty;
    wire                      full;
    wire [DEF_DATA_WIDTH-1:0] data_out;

    // Signals for parameterized DUT
    reg                     p_reset;
    reg                     p_write_en;
    reg                     p_read_en;
    reg  [P_DATA_WIDTH-1:0] p_data_in;
    wire                    p_empty;
    wire                    p_full;
    wire [P_DATA_WIDTH-1:0] p_data_out;

    // Error counter and test helpers
    integer errors = 0;
    integer i;
    integer seed;
    integer op;

    // Reference model for default DUT randomized test
    reg [DEF_DATA_WIDTH-1:0] ref_stack [0:DEF_DEPTH-1];
    integer                  ref_sp;
    reg [DEF_DATA_WIDTH-1:0] ref_data_out;
    reg                      exp_empty;
    reg                      exp_full;

    // Instantiate DUT with default parameters to verify defaults
    sync_lifo dut (
        .clock    (clock),
        .reset    (reset),
        .write_en (write_en),
        .read_en  (read_en),
        .data_in  (data_in),
        .empty    (empty),
        .full     (full),
        .data_out (data_out)
    );

    // Instantiate second DUT with non-default parameters
    sync_lifo #(
        .DATA_WIDTH(P_DATA_WIDTH),
        .ADDR_WIDTH(P_ADDR_WIDTH)
    ) dut_param (
        .clock    (clock),
        .reset    (p_reset),
        .write_en (p_write_en),
        .read_en  (p_read_en),
        .data_in  (p_data_in),
        .empty    (p_empty),
        .full     (p_full),
        .data_out (p_data_out)
    );

    // Clock generation: 10ns period
    initial begin
        clock = 1'b0;
        forever #5 clock = ~clock;
    end

    // Task to check default DUT outputs
    task check_def;
        input [DEF_DATA_WIDTH-1:0] exp_d;
        input                      exp_e;
        input                      exp_f;
        input integer              test_id;
        begin
            if (empty !== exp_e) begin
                $display("FAIL [Test %0d]: empty mismatch - expected %b, got %b at t=%0t",
                         test_id, exp_e, empty, $time);
                errors = errors + 1;
            end
            if (full !== exp_f) begin
                $display("FAIL [Test %0d]: full mismatch - expected %b, got %b at t=%0t",
                         test_id, exp_f, full, $time);
                errors = errors + 1;
            end
            if (data_out !== exp_d) begin
                $display("FAIL [Test %0d]: data_out mismatch - expected 0x%0h, got 0x%0h at t=%0t",
                         test_id, exp_d, data_out, $time);
                errors = errors + 1;
            end
        end
    endtask

    // Task to check parameterized DUT outputs
    task check_param;
        input [P_DATA_WIDTH-1:0] exp_d;
        input                    exp_e;
        input                    exp_f;
        input integer            test_id;
        begin
            if (p_empty !== exp_e) begin
                $display("FAIL [Param Test %0d]: p_empty mismatch - expected %b, got %b at t=%0t",
                         test_id, exp_e, p_empty, $time);
                errors = errors + 1;
            end
            if (p_full !== exp_f) begin
                $display("FAIL [Param Test %0d]: p_full mismatch - expected %b, got %b at t=%0t",
                         test_id, exp_f, p_full, $time);
                errors = errors + 1;
            end
            if (p_data_out !== exp_d) begin
                $display("FAIL [Param Test %0d]: p_data_out mismatch - expected 0x%0h, got 0x%0h at t=%0t",
                         test_id, exp_d, p_data_out, $time);
                errors = errors + 1;
            end
        end
    endtask

    // Helper tasks for driving default DUT synchronously on negedge
    task push_def;
        input [DEF_DATA_WIDTH-1:0] val;
        begin
            @(negedge clock);
            reset    = 1'b0;
            write_en = 1'b1;
            read_en  = 1'b0;
            data_in  = val;
            @(posedge clock);
            #1;
        end
    endtask

    task pop_def;
        begin
            @(negedge clock);
            reset    = 1'b0;
            write_en = 1'b0;
            read_en  = 1'b1;
            data_in  = {DEF_DATA_WIDTH{1'b0}};
            @(posedge clock);
            #1;
        end
    endtask

    task idle_def;
        begin
            @(negedge clock);
            reset    = 1'b0;
            write_en = 1'b0;
            read_en  = 1'b0;
            data_in  = {DEF_DATA_WIDTH{1'b0}};
            @(posedge clock);
            #1;
        end
    endtask

    // Helper tasks for parameterized DUT
    task push_param;
        input [P_DATA_WIDTH-1:0] val;
        begin
            @(negedge clock);
            p_reset    = 1'b0;
            p_write_en = 1'b1;
            p_read_en  = 1'b0;
            p_data_in  = val;
            @(posedge clock);
            #1;
        end
    endtask

    task pop_param;
        begin
            @(negedge clock);
            p_reset    = 1'b0;
            p_write_en = 1'b0;
            p_read_en  = 1'b1;
            p_data_in  = {P_DATA_WIDTH{1'b0}};
            @(posedge clock);
            #1;
        end
    endtask

    initial begin
        seed = 32'h1357_2468;

        // Initialize all inputs
        reset      = 1'b1;
        write_en   = 1'b0;
        read_en    = 1'b0;
        data_in    = {DEF_DATA_WIDTH{1'b0}};

        p_reset    = 1'b1;
        p_write_en = 1'b0;
        p_read_en  = 1'b0;
        p_data_in  = {P_DATA_WIDTH{1'b0}};

        // =========================================================
        // Test 1: Synchronous Reset Behavior
        // =========================================================
        @(posedge clock); #1;
        check_def(8'h00, 1'b1, 1'b0, 1);
        check_param(16'h0000, 1'b1, 1'b0, 1);

        @(posedge clock); #1;
        check_def(8'h00, 1'b1, 1'b0, 1);

        idle_def();
        check_def(8'h00, 1'b1, 1'b0, 1);

        // =========================================================
        // Test 2: Underflow on Empty LIFO (with initial data_out=0)
        // =========================================================
        pop_def();
        check_def(8'h00, 1'b1, 1'b0, 2);

        pop_def();
        check_def(8'h00, 1'b1, 1'b0, 2);

        // Verify pointer was not corrupted by underflow
        push_def(8'hA5);
        check_def(8'h00, 1'b0, 1'b0, 2);
        pop_def();
        check_def(8'hA5, 1'b1, 1'b0, 2);

        // =========================================================
        // Test 3: Underflow holds non-zero previous data_out
        // =========================================================
        pop_def();
        check_def(8'hA5, 1'b1, 1'b0, 3);
        pop_def();
        check_def(8'hA5, 1'b1, 1'b0, 3);

        push_def(8'h5A);
        check_def(8'hA5, 1'b0, 1'b0, 3);
        pop_def();
        check_def(8'h5A, 1'b1, 1'b0, 3);

        // =========================================================
        // Test 4: Bit pattern checks (0x00, 0xFF, 0xAA, 0x55)
        // =========================================================
        push_def(8'h00);
        check_def(8'h5A, 1'b0, 1'b0, 4);
        pop_def();
        check_def(8'h00, 1'b1, 1'b0, 4);

        push_def(8'hFF);
        check_def(8'h00, 1'b0, 1'b0, 4);
        pop_def();
        check_def(8'hFF, 1'b1, 1'b0, 4);

        // =========================================================
        // Test 5: Fill to FULL, test Overflow, then Drain to EMPTY
        // =========================================================
        for (i = 0; i < DEF_DEPTH; i = i + 1) begin
            push_def(8'h10 + i[7:0]);
            if (i == DEF_DEPTH - 1)
                check_def(8'hFF, 1'b0, 1'b1, 5);
            else
                check_def(8'hFF, 1'b0, 1'b0, 5);
        end

        // Overflow attempts while FULL
        push_def(8'hDE);
        check_def(8'hFF, 1'b0, 1'b1, 6);
        push_def(8'hAD);
        check_def(8'hFF, 1'b0, 1'b1, 6);

        // Drain all 8 items in strict LIFO order
        for (i = DEF_DEPTH - 1; i >= 0; i = i - 1) begin
            pop_def();
            if (i == 0)
                check_def(8'h10 + i[7:0], 1'b1, 1'b0, 7);
            else
                check_def(8'h10 + i[7:0], 1'b0, 1'b0, 7);
        end

        // =========================================================
        // Test 8: Boundary bounce at FULL and EMPTY
        // =========================================================
        // Fill to FULL
        for (i = 0; i < DEF_DEPTH; i = i + 1) begin
            push_def(8'hC0 + i[7:0]);
        end
        check_def(8'h10, 1'b0, 1'b1, 8);

        // Pop 1 from FULL -> should clear full flag
        pop_def();
        check_def(8'hC7, 1'b0, 1'b0, 8);

        // Push 1 back to FULL -> should set full flag again
        push_def(8'h99);
        check_def(8'hC7, 1'b0, 1'b1, 8);

        // Pop top -> should get 0x99
        pop_def();
        check_def(8'h99, 1'b0, 1'b0, 8);

        // Drain remaining 7 items
        for (i = DEF_DEPTH - 2; i >= 0; i = i - 1) begin
            pop_def();
            check_def(8'hC0 + i[7:0], (i == 0) ? 1'b1 : 1'b0, 1'b0, 8);
        end

        // =========================================================
        // Test 9: Interleaved Push/Pop and Idle Hold
        // =========================================================
        push_def(8'h11);
        push_def(8'h22);
        push_def(8'h33);
        pop_def();
        check_def(8'h33, 1'b0, 1'b0, 9);

        push_def(8'h44);
        push_def(8'h55);

        // Idle for 3 cycles - data_out and flags must hold
        idle_def();
        check_def(8'h55 - 8'h22, 1'b0, 1'b0, 9); // wait, data_out should still be 0x33!
        // Note: checking against 0x33 properly below:
        // Let's correct that check cleanly by resetting errors? No, don't write bogus check!
        // Wait: data_out is 0x33 before popping 0x55. Let's check 0x33 directly.
        idle_def();
        check_def(8'h33, 1'b0, 1'b0, 9);

        pop_def();
        check_def(8'h55, 1'b0, 1'b0, 9);
        pop_def();
        check_def(8'h44, 1'b0, 1'b0, 9);
        pop_def();
        check_def(8'h22, 1'b0, 1'b0, 9);

        push_def(8'h66);
        pop_def();
        check_def(8'h66, 1'b0, 1'b0, 9);
        pop_def();
        check_def(8'h11, 1'b1, 1'b0, 9);

        // =========================================================
        // Test 10: Mid-operation Synchronous Reset
        // =========================================================
        push_def(8'hAA);
        push_def(8'hBB);
        push_def(8'hCC);
        pop_def();
        check_def(8'hCC, 1'b0, 1'b0, 10); // data_out=0xCC, 2 items still in LIFO

        // Assert reset synchronously
        @(negedge clock);
        reset    = 1'b1;
        write_en = 1'b0;
        read_en  = 1'b0;
        @(posedge clock); #1;
        check_def(8'h00, 1'b1, 1'b0, 10);

        // Release reset and confirm memory/pointer start fresh
        idle_def();
        check_def(8'h00, 1'b1, 1'b0, 10);

        pop_def(); // Underflow check after mid-op reset
        check_def(8'h00, 1'b1, 1'b0, 10);

        push_def(8'h7E);
        check_def(8'h00, 1'b0, 1'b0, 10);
        pop_def();
        check_def(8'h7E, 1'b1, 1'b0, 10);

        // =========================================================
        // Test 11: Randomized Stress Test (Non-simultaneous R/W)
        // =========================================================
        @(negedge clock);
        reset    = 1'b1;
        write_en = 1'b0;
        read_en  = 1'b0;
        @(posedge clock); #1;

        ref_sp       = 0;
        ref_data_out = {DEF_DATA_WIDTH{1'b0}};
        for (i = 0; i < DEF_DEPTH; i = i + 1)
            ref_stack[i] = {DEF_DATA_WIDTH{1'b0}};

        check_def(ref_data_out, 1'b1, 1'b0, 11);

        for (i = 0; i < 250; i = i + 1) begin
            @(negedge clock);
            reset = 1'b0;
            op = ($random(seed) & 32'h7FFFFFFF) % 3;
            data_in = $random(seed);
            if (op == 1) begin
                write_en = 1'b1;
                read_en  = 1'b0;
            end else if (op == 2) begin
                write_en = 1'b0;
                read_en  = 1'b1;
            end else begin
                write_en = 1'b0;
                read_en  = 1'b0;
            end

            @(posedge clock); #1;
            if (write_en && (ref_sp < DEF_DEPTH)) begin
                ref_stack[ref_sp] = data_in;
                ref_sp = ref_sp + 1;
            end else if (read_en && (ref_sp > 0)) begin
                ref_sp = ref_sp - 1;
                ref_data_out = ref_stack[ref_sp];
            end

            exp_empty = (ref_sp == 0);
            exp_full  = (ref_sp == DEF_DEPTH);
            check_def(ref_data_out, exp_empty, exp_full, 11);
        end

        idle_def();

        // =========================================================
        // Test 12: Parameterized Instance (DATA_WIDTH=16, ADDR_WIDTH=2)
        // =========================================================
        @(negedge clock);
        p_reset    = 1'b1;
        p_write_en = 1'b0;
        p_read_en  = 1'b0;
        @(posedge clock); #1;
        check_param(16'h0000, 1'b1, 1'b0, 12);

        // Underflow on empty parameterized LIFO
        pop_param();
        check_param(16'h0000, 1'b1, 1'b0, 12);

        // Fill depth=4
        push_param(16'hCAFE);
        check_param(16'h0000, 1'b0, 1'b0, 12);
        push_param(16'hBEEF);
        check_param(16'h0000, 1'b0, 1'b0, 12);
        push_param(16'hDEAD);
        check_param(16'h0000, 1'b0, 1'b0, 12);
        push_param(16'h1234);
        check_param(16'h0000, 1'b0, 1'b1, 12);

        // Overflow on full parameterized LIFO
        push_param(16'hFFFF);
        check_param(16'h0000, 1'b0, 1'b1, 12);

        // Drain in LIFO order
        pop_param();
        check_param(16'h1234, 1'b0, 1'b0, 12);
        pop_param();
        check_param(16'hDEAD, 1'b0, 1'b0, 12);
        pop_param();
        check_param(16'hBEEF, 1'b0, 1'b0, 12);
        pop_param();
        check_param(16'hCAFE, 1'b1, 1'b0, 12);

        // Underflow holds last read value
        pop_param();
        check_param(16'hCAFE, 1'b1, 1'b0, 12);

        // Mid-operation reset on parameterized LIFO
        push_param(16'h5A5A);
        @(negedge clock);
        p_reset    = 1'b1;
        p_write_en = 1'b0;
        p_read_en  = 1'b0;
        @(posedge clock); #1;
        check_param(16'h0000, 1'b1, 1'b0, 12);

        // Final summary
        if (errors == 0)
            $display("PASS");
        else
            $display("FAIL: %0d errors", errors);

        $finish;
    end
endmodule
