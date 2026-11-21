`timescale 1ns/1ps

module tb;
    reg clk;
    reg arst_n;
    reg signed [15:0] a_real;
    reg signed [15:0] a_imag;
    reg signed [15:0] b_real;
    reg signed [15:0] b_imag;
    wire signed [31:0] result_real;
    wire signed [31:0] result_imag;

    integer errors = 0;
    integer i;
    integer seed = 32'h1234_5678;

    complex_multiplier dut (
        .clk         (clk),
        .arst_n      (arst_n),
        .a_real      (a_real),
        .a_imag      (a_imag),
        .b_real      (b_real),
        .b_imag      (b_imag),
        .result_real (result_real),
        .result_imag (result_imag)
    );

    // 10ns clock period
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Task to drive inputs before a rising edge and check 1-cycle latency after it
    task automatic check_single;
        input signed [15:0] in_ar;
        input signed [15:0] in_ai;
        input signed [15:0] in_br;
        input signed [15:0] in_bi;
        reg signed [31:0] ac, bd, ad, bc;
        reg signed [31:0] exp_real, exp_imag;
        begin
            @(negedge clk);
            a_real = in_ar;
            a_imag = in_ai;
            b_real = in_br;
            b_imag = in_bi;

            ac = in_ar * in_br;
            bd = in_ai * in_bi;
            ad = in_ar * in_bi;
            bc = in_ai * in_br;
            exp_real = ac - bd;
            exp_imag = ad + bc;

            @(posedge clk);
            #1;
            if (result_real !== exp_real || result_imag !== exp_imag) begin
                $display("FAIL: (%0d + %0dj) * (%0d + %0dj) expected (%0d + %0dj), got (%0d + %0dj)",
                         in_ar, in_ai, in_br, in_bi,
                         exp_real, exp_imag, result_real, result_imag);
                errors = errors + 1;
            end
        end
    endtask

    // Back-to-back streaming check (changes inputs every cycle)
    task automatic run_stream_tests;
        input integer count;
        reg signed [15:0] next_ar, next_ai, next_br, next_bi;
        reg signed [31:0] exp_real_q, exp_imag_q;
        reg signed [31:0] ac, bd, ad, bc;
        reg valid_q;
        begin
            valid_q = 1'b0;
            exp_real_q = 32'sd0;
            exp_imag_q = 32'sd0;

            for (i = 0; i < count; i = i + 1) begin
                @(negedge clk);
                if (valid_q) begin
                    if (result_real !== exp_real_q || result_imag !== exp_imag_q) begin
                        $display("FAIL (stream cycle %0d): expected (%0d + %0dj), got (%0d + %0dj)",
                                 i, exp_real_q, exp_imag_q, result_real, result_imag);
                        errors = errors + 1;
                    end
                end

                next_ar = $random(seed);
                next_ai = $random(seed);
                next_br = $random(seed);
                next_bi = $random(seed);

                a_real = next_ar;
                a_imag = next_ai;
                b_real = next_br;
                b_imag = next_bi;

                ac = next_ar * next_br;
                bd = next_ai * next_bi;
                ad = next_ar * next_bi;
                bc = next_ai * next_br;
                exp_real_q = ac - bd;
                exp_imag_q = ad + bc;
                valid_q = 1'b1;

                @(posedge clk);
            end

            @(negedge clk);
            if (valid_q) begin
                if (result_real !== exp_real_q || result_imag !== exp_imag_q) begin
                    $display("FAIL (stream final cycle): expected (%0d + %0dj), got (%0d + %0dj)",
                             exp_real_q, exp_imag_q, result_real, result_imag);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        a_real = 16'sd0;
        a_imag = 16'sd0;
        b_real = 16'sd0;
        b_imag = 16'sd0;
        arst_n = 1'b0;

        // 1. Test initial reset state
        #3;
        if (result_real !== 32'sd0 || result_imag !== 32'sd0) begin
            $display("FAIL: initial async reset expected (0 + 0j), got (%0d + %0dj)",
                     result_real, result_imag);
            errors = errors + 1;
        end

        // Hold reset across a clock edge with non-zero inputs
        a_real = 16'sd123;
        a_imag = -16'sd456;
        b_real = 16'sd789;
        b_imag = 16'sd321;
        @(posedge clk);
        #1;
        if (result_real !== 32'sd0 || result_imag !== 32'sd0) begin
            $display("FAIL: outputs not held at 0 during reset, got (%0d + %0dj)",
                     result_real, result_imag);
            errors = errors + 1;
        end

        // Release reset
        @(negedge clk);
        arst_n = 1'b1;

        // 2. Normal operation and basic identities
        check_single(16'sd0,    16'sd0,    16'sd0,    16'sd0);
        check_single(16'sd1,    16'sd0,    16'sd1,    16'sd0);
        check_single(16'sd0,    16'sd1,    16'sd0,    16'sd1);     // j * j = -1
        check_single(16'sd3,    16'sd4,    16'sd5,    16'sd6);     // -9 + 38j
        check_single(-16'sd3,   16'sd4,    16'sd5,   -16'sd6);     // 9 + 38j
        check_single(-16'sd7,  -16'sd8,   -16'sd9,  -16'sd10);     // -17 + 142j
        check_single(16'sd100, -16'sd200,  16'sd0,    16'sd0);
        check_single(16'sd0,    16'sd0,   -16'sd500,  16'sd600);

        // 3. Edge and corner cases (16-bit signed extremes)
        check_single(16'sd32767,  16'sd32767,  16'sd32767,  16'sd32767);
        check_single(-16'sd32768, 16'sd0,     -16'sd32768,  16'sd0);
        check_single(16'sd0,     -16'sd32768,  16'sd0,     -16'sd32768);
        check_single(-16'sd32768, 16'sd32767,  16'sd32767, -16'sd32768);
        check_single(-16'sd32768,-16'sd32768, -16'sd32768,-16'sd32768);
        check_single(16'sd32767, -16'sd32768, -16'sd32768,  16'sd32767);
        check_single(16'sd1,     -16'sd1,      16'sd32767, -16'sd32768);

        // 4. Test asynchronous reset while outputs are non-zero (mid-cycle)
        check_single(16'sd111, 16'sd222, 16'sd333, 16'sd444);
        @(negedge clk);
        arst_n = 1'b0;
        #1;
        if (result_real !== 32'sd0 || result_imag !== 32'sd0) begin
            $display("FAIL: async reset assertion mid-cycle expected (0 + 0j), got (%0d + %0dj)",
                     result_real, result_imag);
            errors = errors + 1;
        end
        @(posedge clk);
        #1;
        if (result_real !== 32'sd0 || result_imag !== 32'sd0) begin
            $display("FAIL: outputs changed while arst_n=0, got (%0d + %0dj)",
                     result_real, result_imag);
            errors = errors + 1;
        end

        @(negedge clk);
        arst_n = 1'b1;

        // 5. Back-to-back streaming randomized tests (verifying 1-cycle latency throughput)
        run_stream_tests(100);

        if (errors == 0)
            $display("PASS");
        else
            $display("FAIL: %0d errors", errors);

        $finish;
    end
endmodule
