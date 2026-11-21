`timescale 1ns/1ps

module tb;

    reg clk;
    reg rst;

    // Signals for default WIDTH = 6 instance
    reg        start_w6;
    reg  [5:0] dividend_w6;
    reg  [5:0] divisor_w6;
    wire [5:0] quotient_w6;
    wire [5:0] remainder_w6;
    wire       valid_w6;

    // Signals for WIDTH = 3 instance (non-power-of-2, matches spec example)
    reg        start_w3;
    reg  [2:0] dividend_w3;
    reg  [2:0] divisor_w3;
    wire [2:0] quotient_w3;
    wire [2:0] remainder_w3;
    wire       valid_w3;

    // Signals for WIDTH = 4 instance (power-of-2)
    reg        start_w4;
    reg  [3:0] dividend_w4;
    reg  [3:0] divisor_w4;
    wire [3:0] quotient_w4;
    wire [3:0] remainder_w4;
    wire       valid_w4;

    // Signals for WIDTH = 8 instance (larger power-of-2)
    reg        start_w8;
    reg  [7:0] dividend_w8;
    reg  [7:0] divisor_w8;
    wire [7:0] quotient_w8;
    wire [7:0] remainder_w8;
    wire       valid_w8;

    integer errors = 0;
    integer seed   = 32'hCAFE_BABE;
    integer i, j, r1, r2;

    // Instantiate DUTs
    restoring_division dut_w6 (
        .clk       (clk),
        .rst       (rst),
        .start     (start_w6),
        .dividend  (dividend_w6),
        .divisor   (divisor_w6),
        .quotient  (quotient_w6),
        .remainder (remainder_w6),
        .valid     (valid_w6)
    );

    restoring_division #(.WIDTH(3)) dut_w3 (
        .clk       (clk),
        .rst       (rst),
        .start     (start_w3),
        .dividend  (dividend_w3),
        .divisor   (divisor_w3),
        .quotient  (quotient_w3),
        .remainder (remainder_w3),
        .valid     (valid_w3)
    );

    restoring_division #(.WIDTH(4)) dut_w4 (
        .clk       (clk),
        .rst       (rst),
        .start     (start_w4),
        .dividend  (dividend_w4),
        .divisor   (divisor_w4),
        .quotient  (quotient_w4),
        .remainder (remainder_w4),
        .valid     (valid_w4)
    );

    restoring_division #(.WIDTH(8)) dut_w8 (
        .clk       (clk),
        .rst       (rst),
        .start     (start_w8),
        .dividend  (dividend_w8),
        .divisor   (divisor_w8),
        .quotient  (quotient_w8),
        .remainder (remainder_w8),
        .valid     (valid_w8)
    );

    // 100 MHz clock (10 ns period)
    always #5 clk = ~clk;

    task check_all_zero;
        input [8*32-1:0] ctx;
        begin
            if (quotient_w3 !== 3'd0 || remainder_w3 !== 3'd0 || valid_w3 !== 1'b0) begin
                $display("FAIL: %0s [W=3] expected all 0s, got q=%b r=%b v=%b",
                         ctx, quotient_w3, remainder_w3, valid_w3);
                errors = errors + 1;
            end
            if (quotient_w4 !== 4'd0 || remainder_w4 !== 4'd0 || valid_w4 !== 1'b0) begin
                $display("FAIL: %0s [W=4] expected all 0s, got q=%b r=%b v=%b",
                         ctx, quotient_w4, remainder_w4, valid_w4);
                errors = errors + 1;
            end
            if (quotient_w6 !== 6'd0 || remainder_w6 !== 6'd0 || valid_w6 !== 1'b0) begin
                $display("FAIL: %0s [W=6] expected all 0s, got q=%b r=%b v=%b",
                         ctx, quotient_w6, remainder_w6, valid_w6);
                errors = errors + 1;
            end
            if (quotient_w8 !== 8'd0 || remainder_w8 !== 8'd0 || valid_w8 !== 1'b0) begin
                $display("FAIL: %0s [W=8] expected all 0s, got q=%b r=%b v=%b",
                         ctx, quotient_w8, remainder_w8, valid_w8);
                errors = errors + 1;
            end
        end
    endtask

    task run_w3;
        input [2:0] dvd;
        input [2:0] dvs;
        reg   [2:0] exp_q;
        reg   [2:0] exp_r;
        integer     cyc;
        begin
            exp_q = dvd / dvs;
            exp_r = dvd % dvs;

            @(negedge clk);
            dividend_w3 = dvd;
            divisor_w3  = dvs;
            start_w3    = 1'b1;

            @(negedge clk);
            start_w3 = 1'b0;

            cyc = 1;
            while (valid_w3 !== 1'b1 && cyc < 8) begin
                @(negedge clk);
                cyc = cyc + 1;
            end

            if (valid_w3 !== 1'b1) begin
                $display("FAIL: [W=3] Timeout waiting for valid (dvd=%0d, dvs=%0d)", dvd, dvs);
                errors = errors + 1;
            end else begin
                if (quotient_w3 !== exp_q || remainder_w3 !== exp_r) begin
                    $display("FAIL: [W=3] dvd=%0d dvs=%0d expected q=%0d r=%0d, got q=%0d r=%0d",
                             dvd, dvs, exp_q, exp_r, quotient_w3, remainder_w3);
                    errors = errors + 1;
                end
                @(negedge clk);
                if (valid_w3 !== 1'b0) begin
                    $display("FAIL: [W=3] valid stayed high >1 cycle (dvd=%0d, dvs=%0d)", dvd, dvs);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task run_w4;
        input [3:0] dvd;
        input [3:0] dvs;
        reg   [3:0] exp_q;
        reg   [3:0] exp_r;
        integer     cyc;
        begin
            exp_q = dvd / dvs;
            exp_r = dvd % dvs;

            @(negedge clk);
            dividend_w4 = dvd;
            divisor_w4  = dvs;
            start_w4    = 1'b1;

            @(negedge clk);
            start_w4 = 1'b0;

            cyc = 1;
            while (valid_w4 !== 1'b1 && cyc < 9) begin
                @(negedge clk);
                cyc = cyc + 1;
            end

            if (valid_w4 !== 1'b1) begin
                $display("FAIL: [W=4] Timeout waiting for valid (dvd=%0d, dvs=%0d)", dvd, dvs);
                errors = errors + 1;
            end else begin
                if (quotient_w4 !== exp_q || remainder_w4 !== exp_r) begin
                    $display("FAIL: [W=4] dvd=%0d dvs=%0d expected q=%0d r=%0d, got q=%0d r=%0d",
                             dvd, dvs, exp_q, exp_r, quotient_w4, remainder_w4);
                    errors = errors + 1;
                end
                @(negedge clk);
                if (valid_w4 !== 1'b0) begin
                    $display("FAIL: [W=4] valid stayed high >1 cycle (dvd=%0d, dvs=%0d)", dvd, dvs);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task run_w6;
        input [5:0] dvd;
        input [5:0] dvs;
        reg   [5:0] exp_q;
        reg   [5:0] exp_r;
        integer     cyc;
        begin
            exp_q = dvd / dvs;
            exp_r = dvd % dvs;

            @(negedge clk);
            dividend_w6 = dvd;
            divisor_w6  = dvs;
            start_w6    = 1'b1;

            @(negedge clk);
            start_w6 = 1'b0;

            cyc = 1;
            while (valid_w6 !== 1'b1 && cyc < 12) begin
                @(negedge clk);
                cyc = cyc + 1;
            end

            if (valid_w6 !== 1'b1) begin
                $display("FAIL: [W=6] Timeout waiting for valid (dvd=%0d, dvs=%0d)", dvd, dvs);
                errors = errors + 1;
            end else begin
                if (quotient_w6 !== exp_q || remainder_w6 !== exp_r) begin
                    $display("FAIL: [W=6] dvd=%0d dvs=%0d expected q=%0d r=%0d, got q=%0d r=%0d",
                             dvd, dvs, exp_q, exp_r, quotient_w6, remainder_w6);
                    errors = errors + 1;
                end
                @(negedge clk);
                if (valid_w6 !== 1'b0) begin
                    $display("FAIL: [W=6] valid stayed high >1 cycle (dvd=%0d, dvs=%0d)", dvd, dvs);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task run_w8;
        input [7:0] dvd;
        input [7:0] dvs;
        reg   [7:0] exp_q;
        reg   [7:0] exp_r;
        integer     cyc;
        begin
            exp_q = dvd / dvs;
            exp_r = dvd % dvs;

            @(negedge clk);
            dividend_w8 = dvd;
            divisor_w8  = dvs;
            start_w8    = 1'b1;

            @(negedge clk);
            start_w8 = 1'b0;

            cyc = 1;
            while (valid_w8 !== 1'b1 && cyc < 14) begin
                @(negedge clk);
                cyc = cyc + 1;
            end

            if (valid_w8 !== 1'b1) begin
                $display("FAIL: [W=8] Timeout waiting for valid (dvd=%0d, dvs=%0d)", dvd, dvs);
                errors = errors + 1;
            end else begin
                if (quotient_w8 !== exp_q || remainder_w8 !== exp_r) begin
                    $display("FAIL: [W=8] dvd=%0d dvs=%0d expected q=%0d r=%0d, got q=%0d r=%0d",
                             dvd, dvs, exp_q, exp_r, quotient_w8, remainder_w8);
                    errors = errors + 1;
                end
                @(negedge clk);
                if (valid_w8 !== 1'b0) begin
                    $display("FAIL: [W=8] valid stayed high >1 cycle (dvd=%0d, dvs=%0d)", dvd, dvs);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;

        start_w3 = 1'b0; dividend_w3 = 3'd0; divisor_w3 = 3'd1;
        start_w4 = 1'b0; dividend_w4 = 4'd0; divisor_w4 = 4'd1;
        start_w6 = 1'b0; dividend_w6 = 6'd0; divisor_w6 = 6'd1;
        start_w8 = 1'b0; dividend_w8 = 8'd0; divisor_w8 = 8'd1;

        // 1. Test initial asynchronous reset before any clock edge
        #1;
        check_all_zero("initial async reset");

        // Hold reset across two clock edges
        repeat (2) @(posedge clk);
        #1;
        check_all_zero("reset held across clocks");

        // Release reset
        @(negedge clk);
        rst = 1'b1;
        @(negedge clk);
        check_all_zero("idle after reset release");

        // 2. Spec example and exhaustive test for WIDTH = 3 (1 <= divisor <= dividend <= 7)
        run_w3(3'd7, 3'd5);
        for (i = 1; i <= 7; i = i + 1) begin
            for (j = 1; j <= i; j = j + 1) begin
                run_w3(i[2:0], j[2:0]);
            end
        end

        // 3. Exhaustive test for WIDTH = 4 (1 <= divisor <= dividend <= 15)
        for (i = 1; i <= 15; i = i + 1) begin
            for (j = 1; j <= i; j = j + 1) begin
                run_w4(i[3:0], j[3:0]);
            end
        end

        // 4. Corner cases & pseudo-random tests for default WIDTH = 6
        run_w6(6'd1,  6'd1);
        run_w6(6'd63, 6'd1);
        run_w6(6'd63, 6'd63);
        run_w6(6'd63, 6'd62);
        run_w6(6'd63, 6'd2);
        run_w6(6'd63, 6'd32);
        run_w6(6'd32, 6'd1);
        run_w6(6'd32, 6'd2);
        run_w6(6'd32, 6'd16);
        run_w6(6'd32, 6'd31);
        run_w6(6'd32, 6'd3);
        run_w6(6'd60, 6'd10);
        run_w6(6'd61, 6'd10);
        run_w6(6'd59, 6'd10);
        run_w6(6'b101010, 6'b010101);
        run_w6(6'b101010, 6'b001011);
        run_w6(6'b110110, 6'b011011);

        for (i = 0; i < 40; i = i + 1) begin
            r1 = ($random(seed) & 32'h7fffffff) % 63 + 1;
            r2 = ($random(seed) & 32'h7fffffff) % 63 + 1;
            if (r1 >= r2) run_w6(r1[5:0], r2[5:0]);
            else          run_w6(r2[5:0], r1[5:0]);
        end

        // 5. Corner cases & pseudo-random tests for WIDTH = 8
        run_w8(8'd1,   8'd1);
        run_w8(8'd255, 8'd1);
        run_w8(8'd255, 8'd255);
        run_w8(8'd255, 8'd254);
        run_w8(8'd255, 8'd128);
        run_w8(8'd255, 8'd127);
        run_w8(8'd128, 8'd128);
        run_w8(8'd128, 8'd3);
        run_w8(8'd254, 8'd2);
        run_w8(8'd255, 8'd16);
        run_w8(8'd255, 8'd15);
        run_w8(8'b10101010, 8'b01010101);
        run_w8(8'b10101010, 8'b00010001);

        for (i = 0; i < 40; i = i + 1) begin
            r1 = ($random(seed) & 32'h7fffffff) % 255 + 1;
            r2 = ($random(seed) & 32'h7fffffff) % 255 + 1;
            if (r1 >= r2) run_w8(r1[7:0], r2[7:0]);
            else          run_w8(r2[7:0], r1[7:0]);
        end

        // 6. Mid-operation asynchronous reset & recovery test
        @(negedge clk);
        dividend_w6 = 6'd63;
        divisor_w6  = 6'd5;
        start_w6    = 1'b1;
        dividend_w8 = 8'd255;
        divisor_w8  = 8'd13;
        start_w8    = 1'b1;

        @(negedge clk);
        start_w6 = 1'b0;
        start_w8 = 1'b0;

        @(negedge clk);
        #2;
        rst = 1'b0;
        #1;
        if (quotient_w6 !== 6'd0 || remainder_w6 !== 6'd0 || valid_w6 !== 1'b0) begin
            $display("FAIL: [W=6] Async reset mid-op did not clear outputs immediately (q=%0d r=%0d v=%b)",
                     quotient_w6, remainder_w6, valid_w6);
            errors = errors + 1;
        end
        if (quotient_w8 !== 8'd0 || remainder_w8 !== 8'd0 || valid_w8 !== 1'b0) begin
            $display("FAIL: [W=8] Async reset mid-op did not clear outputs immediately (q=%0d r=%0d v=%b)",
                     quotient_w8, remainder_w8, valid_w8);
            errors = errors + 1;
        end

        @(negedge clk);
        rst = 1'b1;
        @(negedge clk);
        check_all_zero("after mid-op reset release");

        // Verify clean recovery after async reset
        run_w6(6'd55, 6'd7);
        run_w8(8'd200, 8'd11);

        // 7. Idle stability check (no spurious valid pulses when start == 0)
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk);
            if (valid_w3 !== 1'b0 || valid_w4 !== 1'b0 || valid_w6 !== 1'b0 || valid_w8 !== 1'b0) begin
                $display("FAIL: Spurious valid asserted while idle");
                errors = errors + 1;
            end
        end

        if (errors == 0) begin
            $display("PASS");
        end else begin
            $display("FAIL: %0d errors", errors);
        end
        $finish;
    end

endmodule
