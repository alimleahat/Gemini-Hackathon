`timescale 1ns/1ps

module tb;

    reg         clk_in;
    reg         rst_in;
    reg  [63:0] encoder_data_in;
    reg  [7:0]  encoder_control_in;
    wire [65:0] encoder_data_out;

    integer errors = 0;
    integer i;
    reg [65:0] prev_expected;
    reg [65:0] expected;

    // Instantiate DUT
    encoder_64b66b dut (
        .clk_in             (clk_in),
        .rst_in             (rst_in),
        .encoder_data_in    (encoder_data_in),
        .encoder_control_in (encoder_control_in),
        .encoder_data_out   (encoder_data_out)
    );

    // 10ns clock period
    initial begin
        clk_in = 1'b0;
        forever #5 clk_in = ~clk_in;
    end

    // Helper task: apply inputs at negedge, verify registered latency, check output after posedge
    task automatic apply_and_check;
        input [63:0] data_val;
        input [7:0]  ctrl_val;
        input [8*40-1:0] test_name;
        begin
            expected = (ctrl_val == 8'h00) ? {2'b01, data_val} : {2'b10, 64'h0000000000000000};

            @(negedge clk_in);
            encoder_data_in    = data_val;
            encoder_control_in = ctrl_val;
            #1;

            // Verify output does not change combinationally before posedge clk_in
            if (encoder_data_out !== prev_expected) begin
                $display("FAIL: [%0s] Premature output change before posedge clk_in: expected %017h, got %017h",
                         test_name, prev_expected, encoder_data_out);
                errors = errors + 1;
            end

            @(posedge clk_in);
            #1;

            // Verify 1-cycle latency output
            if (encoder_data_out !== expected) begin
                $display("FAIL: [%0s] Output mismatch (data=%016h, ctrl=%02h): expected %017h, got %017h",
                         test_name, data_val, ctrl_val, expected, encoder_data_out);
                errors = errors + 1;
            end

            prev_expected = expected;
        end
    endtask

    initial begin
        // Initialize signals
        rst_in             = 1'b1;
        encoder_data_in    = 64'hFFFFFFFFFFFFFFFF;
        encoder_control_in = 8'h00;
        prev_expected      = 66'd0;

        // 1. Test asynchronous reset at startup (before any posedge)
        #1;
        if (encoder_data_out !== 66'd0) begin
            $display("FAIL: [Async Reset Init] Expected 0 during reset, got %017h", encoder_data_out);
            errors = errors + 1;
        end

        // Hold reset across multiple clock edges with non-zero inputs
        repeat (3) begin
            @(posedge clk_in);
            #1;
            if (encoder_data_out !== 66'd0) begin
                $display("FAIL: [Reset Hold] Expected 0 while rst_in=1, got %017h", encoder_data_out);
                errors = errors + 1;
            end
        end

        // Release reset at negedge and verify first post-reset cycle
        @(negedge clk_in);
        rst_in             = 1'b0;
        encoder_data_in    = 64'h0000000000000000;
        encoder_control_in = 8'h00;
        #1;
        if (encoder_data_out !== 66'd0) begin
            $display("FAIL: [Reset Release] Expected 0 before posedge after reset release, got %017h", encoder_data_out);
            errors = errors + 1;
        end
        @(posedge clk_in);
        #1;
        prev_expected = {2'b01, 64'h0000000000000000};
        if (encoder_data_out !== prev_expected) begin
            $display("FAIL: [Post-Reset Cycle] Expected %017h, got %017h", prev_expected, encoder_data_out);
            errors = errors + 1;
        end

        // 2. Specification Examples
        apply_and_check(64'hA5A5A5A5A5A5A5A5, 8'b00000000, "Spec Example 1 (Pure Data)");
        apply_and_check(64'hA5A5A5A5A5A5A5A5, 8'b00001111, "Spec Example 2 (Control)");

        // 3. Test asynchronous reset mid-operation (away from posedge clk_in)
        apply_and_check(64'h123456789ABCDEF0, 8'b00000000, "Pre-Async Reset Load");
        @(negedge clk_in);
        #1;
        rst_in = 1'b1;
        #1; // Must clear immediately without waiting for posedge clk_in
        if (encoder_data_out !== 66'd0) begin
            $display("FAIL: [Mid-op Async Reset] Expected immediate 0 when rst_in=1, got %017h", encoder_data_out);
            errors = errors + 1;
        end
        @(posedge clk_in);
        #1;
        if (encoder_data_out !== 66'd0) begin
            $display("FAIL: [Mid-op Reset Clock] Expected 0 at posedge while rst_in=1, got %017h", encoder_data_out);
            errors = errors + 1;
        end

        // Deassert reset and verify recovery
        @(negedge clk_in);
        rst_in             = 1'b0;
        encoder_data_in    = 64'h0000000000000000;
        encoder_control_in = 8'hFF;
        @(posedge clk_in);
        #1;
        prev_expected = {2'b10, 64'h0000000000000000};
        if (encoder_data_out !== prev_expected) begin
            $display("FAIL: [Post-Mid-op Recovery] Expected %017h, got %017h", prev_expected, encoder_data_out);
            errors = errors + 1;
        end

        // 4. Pure data edge cases (control = 8'h00)
        apply_and_check(64'h0000000000000000, 8'h00, "Data All Zeros");
        apply_and_check(64'hFFFFFFFFFFFFFFFF, 8'h00, "Data All Ones");
        apply_and_check(64'h5555555555555555, 8'h00, "Data Alternating 55");
        apply_and_check(64'hAAAAAAAAAAAAAAAA, 8'h00, "Data Alternating AA");
        apply_and_check(64'h0123456789ABCDEF, 8'h00, "Data Incremental");
        apply_and_check(64'hFEDCBA9876543210, 8'h00, "Data Decremental");

        // Walking 1s across all 64 bits of data
        for (i = 0; i < 64; i = i + 1) begin
            apply_and_check(64'd1 << i, 8'h00, "Data Walking 1");
        end

        // 5. Exhaustive check of all 256 control word values
        for (i = 0; i < 256; i = i + 1) begin
            apply_and_check(64'hCAFEBABEDEADBEEF ^ {i[7:0], 56'd0}, i[7:0], "Exhaustive Ctrl");
        end

        // 6. Back-to-back switching between pure data and control words
        apply_and_check(64'h1122334455667788, 8'h00, "B2B Data 1");
        apply_and_check(64'h1122334455667788, 8'h01, "B2B Ctrl LSB");
        apply_and_check(64'h99AABBCCDDEEFF00, 8'h00, "B2B Data 2");
        apply_and_check(64'h99AABBCCDDEEFF00, 8'h80, "B2B Ctrl MSB");
        apply_and_check(64'h0000000000000001, 8'hFF, "B2B Ctrl All Ones");
        apply_and_check(64'h8000000000000000, 8'h00, "B2B Data MSB");

        // 7. Randomized stress test
        for (i = 0; i < 100; i = i + 1) begin
            if ((i % 3) == 0)
                apply_and_check({$random, $random}, 8'h00, "Random Pure Data");
            else
                apply_and_check({$random, $random}, ($random & 8'hFF) | 8'h01, "Random Control");
        end

        if (errors == 0)
            $display("PASS");
        else
            $display("FAIL: %0d errors", errors);

        $finish;
    end

endmodule
