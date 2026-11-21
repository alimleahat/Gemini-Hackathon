`timescale 1ns/1ps

module tb;

    reg         clk;
    reg         reset;
    reg         start;
    reg  [14:0] plaintext;
    reg  [44:0] key;
    wire [14:0] ciphertext;
    wire        done;

    integer errors = 0;
    integer seed   = 32'h1357_2468;
    integer i;

    // Instantiate DUT
    hill_cipher dut (
        .clk        (clk),
        .reset      (reset),
        .start      (start),
        .plaintext  (plaintext),
        .key        (key),
        .ciphertext (ciphertext),
        .done       (done)
    );

    // 10ns clock period
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Golden reference function for 3x3 Hill cipher mod 26
    function [14:0] calc_hill;
        input [14:0] pt;
        input [44:0] k;
        integer p0, p1, p2;
        integer k00, k01, k02;
        integer k10, k11, k12;
        integer k20, k21, k22;
        integer c0, c1, c2;
        begin
            p0 = pt[14:10];
            p1 = pt[9:5];
            p2 = pt[4:0];

            k00 = k[44:40]; k01 = k[39:35]; k02 = k[34:30];
            k10 = k[29:25]; k11 = k[24:20]; k12 = k[19:15];
            k20 = k[14:10]; k21 = k[9:5];   k22 = k[4:0];

            c0 = (k00 * p0 + k01 * p1 + k02 * p2) % 26;
            c1 = (k10 * p0 + k11 * p1 + k12 * p2) % 26;
            c2 = (k20 * p0 + k21 * p1 + k22 * p2) % 26;

            calc_hill = {c0[4:0], c1[4:0], c2[4:0]};
        end
    endfunction

    // Helper function to pack 3 5-bit letters
    function [14:0] pack_vec;
        input [4:0] a, b, c;
        begin
            pack_vec = {a, b, c};
        end
    endfunction

    // Helper function to pack 3x3 key matrix
    function [44:0] pack_key;
        input [4:0] k00, k01, k02;
        input [4:0] k10, k11, k12;
        input [4:0] k20, k21, k22;
        begin
            pack_key = {k00, k01, k02, k10, k11, k12, k20, k21, k22};
        end
    endfunction

    // Task to execute one encryption transaction and check result & latency
    task run_encryption;
        input [14:0] pt;
        input [44:0] k;
        input integer gap_cycles;
        reg   [14:0] exp_ct;
        integer      cyc;
        reg          got_done;
        begin
            exp_ct   = calc_hill(pt, k);
            got_done = 1'b0;

            // Optional idle gap before asserting start
            repeat (gap_cycles) @(negedge clk);
            if (gap_cycles == 0) @(negedge clk);

            // Apply inputs and pulse start for 1 clock cycle
            plaintext = pt;
            key       = k;
            start     = 1'b1;

            // Wait for rising edge where start is sampled
            @(posedge clk);
            @(negedge clk);
            start = 1'b0;

            // Poll for done over subsequent clock edges
            for (cyc = 1; cyc <= 10; cyc = cyc + 1) begin
                @(posedge clk);
                #1;
                if (done === 1'b1 && !got_done) begin
                    got_done = 1'b1;
                    // Spec states 3 clock cycle latency after applying start
                    if (cyc < 2 || cyc > 4) begin
                        $display("FAIL: Unexpected latency=%0d cycles after start edge (expected ~3 cycles) for pt=%b", cyc, pt);
                        errors = errors + 1;
                    end
                    if (ciphertext !== exp_ct) begin
                        $display("FAIL: Ciphertext mismatch for pt=[%0d,%0d,%0d] -> expected [%0d,%0d,%0d] (%b), got [%0d,%0d,%0d] (%b)",
                                 pt[14:10], pt[9:5], pt[4:0],
                                 exp_ct[14:10], exp_ct[9:5], exp_ct[4:0], exp_ct,
                                 ciphertext[14:10], ciphertext[9:5], ciphertext[4:0], ciphertext);
                        errors = errors + 1;
                    end
                end
            end

            if (!got_done) begin
                $display("FAIL: Timeout waiting for done=1 for pt=[%0d,%0d,%0d], key=%h",
                         pt[14:10], pt[9:5], pt[4:0], k);
                errors = errors + 1;
            end
        end
    endtask

    // Task to run back-to-back without extra polling cycles after done
    task run_back_to_back;
        input [14:0] pt;
        input [44:0] k;
        reg   [14:0] exp_ct;
        integer      cyc;
        reg          got_done;
        begin
            exp_ct   = calc_hill(pt, k);
            got_done = 1'b0;

            @(negedge clk);
            plaintext = pt;
            key       = k;
            start     = 1'b1;

            @(posedge clk);
            @(negedge clk);
            start = 1'b0;

            cyc = 0;
            while (!got_done && cyc < 10) begin
                @(posedge clk);
                #1;
                cyc = cyc + 1;
                if (done === 1'b1) begin
                    got_done = 1'b1;
                    if (cyc < 2 || cyc > 4) begin
                        $display("FAIL: Back-to-back latency=%0d cycles (expected ~3) for pt=%b", cyc, pt);
                        errors = errors + 1;
                    end
                    if (ciphertext !== exp_ct) begin
                        $display("FAIL: Back-to-back ciphertext mismatch for pt=[%0d,%0d,%0d] -> expected %b, got %b",
                                 pt[14:10], pt[9:5], pt[4:0], exp_ct, ciphertext);
                        errors = errors + 1;
                    end
                end
            end

            if (!got_done) begin
                $display("FAIL: Back-to-back timeout waiting for done=1 for pt=%b", pt);
                errors = errors + 1;
            end
        end
    endtask

    // Global watchdog
    initial begin
        #100000;
        $display("FAIL: Global simulation timeout reached");
        errors = errors + 1;
        $finish;
    end

    initial begin
        // Initialize inputs
        reset     = 1'b0;
        start     = 1'b0;
        plaintext = 15'd0;
        key       = 45'd0;

        // ------------------------------------------------------------
        // 1. Asynchronous Reset Test
        // ------------------------------------------------------------
        #2;
        reset = 1'b1;
        #1; // Asynchronous check before any clock edge
        if (ciphertext !== 15'd0) begin
            $display("FAIL: Async reset did not clear ciphertext immediately (got %b, expected 0)", ciphertext);
            errors = errors + 1;
        end

        repeat (2) @(posedge clk);
        #1;
        if (ciphertext !== 15'd0) begin
            $display("FAIL: Ciphertext not 0 while reset is HIGH (got %b)", ciphertext);
            errors = errors + 1;
        end
        if (done !== 1'b0) begin
            $display("FAIL: done not 0 after reset clock edges (got %b)", done);
            errors = errors + 1;
        end

        @(negedge clk);
        reset = 1'b0;

        // ------------------------------------------------------------
        // 2. Idle Behavior Check (start == 0)
        // ------------------------------------------------------------
        plaintext = pack_vec(5'd2, 5'd0, 5'd19);
        key       = pack_key(5'd3, 5'd10, 5'd20,
                             5'd1, 5'd9,  5'd15,
                             5'd8, 5'd7,  5'd17);
        repeat (4) begin
            @(posedge clk);
            #1;
            if (done !== 1'b0) begin
                $display("FAIL: done asserted while start remained LOW");
                errors = errors + 1;
            end
        end

        // ------------------------------------------------------------
        // 3. Specification Example: "CAT" -> "UBB"
        // ------------------------------------------------------------
        run_encryption(
            pack_vec(5'd2, 5'd0, 5'd19),
            pack_key(5'd3, 5'd10, 5'd20,
                     5'd1, 5'd9,  5'd15,
                     5'd8, 5'd7,  5'd17),
            1
        );

        // ------------------------------------------------------------
        // 4. Edge and Corner Cases
        // ------------------------------------------------------------
        // 4a. All-zero plaintext ("AAA") with non-zero key
        run_encryption(
            pack_vec(5'd0, 5'd0, 5'd0),
            pack_key(5'd25, 5'd14, 5'd7,
                     5'd3,  5'd19, 5'd11,
                     5'd8,  5'd22, 5'd5),
            1
        );

        // 4b. All-zero key with max plaintext ("ZZZ")
        run_encryption(
            pack_vec(5'd25, 5'd25, 5'd25),
            pack_key(5'd0, 5'd0, 5'd0,
                     5'd0, 5'd0, 5'd0,
                     5'd0, 5'd0, 5'd0),
            1
        );

        // 4c. Identity key matrix
        run_encryption(
            pack_vec(5'd0, 5'd13, 5'd25),
            pack_key(5'd1, 5'd0, 5'd0,
                     5'd0, 5'd1, 5'd0,
                     5'd0, 5'd0, 5'd1),
            1
        );

        // 4d. Maximum intermediate sum (25*25*3 = 1875 -> 1875 mod 26 = 3)
        run_encryption(
            pack_vec(5'd25, 5'd25, 5'd25),
            pack_key(5'd25, 5'd25, 5'd25,
                     5'd25, 5'd25, 5'd25,
                     5'd25, 5'd25, 5'd25),
            1
        );

        // 4e. Modulo 26 boundary cases: 25, 26, 27 and 51, 52, 53
        run_encryption(
            pack_vec(5'd10, 5'd10, 5'd5),
            pack_key(5'd1, 5'd1, 5'd1,
                     5'd2, 5'd2, 5'd2,
                     5'd0, 5'd0, 5'd0),
            1
        );
        run_encryption(
            pack_vec(5'd10, 5'd10, 5'd6),
            pack_key(5'd1, 5'd1, 5'd1,
                     5'd2, 5'd2, 5'd2,
                     5'd1, 5'd1, 5'd2),
            1
        );
        run_encryption(
            pack_vec(5'd10, 5'd10, 5'd7),
            pack_key(5'd1, 5'd1, 5'd1,
                     5'd2, 5'd2, 5'd2,
                     5'd1, 5'd1, 5'd3),
            1
        );

        // 4f. Asymmetric matrix & vector to catch row/col or bit-order swaps
        run_encryption(
            pack_vec(5'd1, 5'd2, 5'd3),
            pack_key(5'd1, 5'd2, 5'd3,
                     5'd4, 5'd5, 5'd6,
                     5'd7, 5'd8, 5'd9),
            1
        );

        // 4g. Single-element selection tests (verify exact bit mapping)
        run_encryption(
            pack_vec(5'd1, 5'd0, 5'd0),
            pack_key(5'd11, 5'd12, 5'd13,
                     5'd14, 5'd15, 5'd16,
                     5'd17, 5'd18, 5'd19),
            1
        );
        run_encryption(
            pack_vec(5'd0, 5'd1, 5'd0),
            pack_key(5'd11, 5'd12, 5'd13,
                     5'd14, 5'd15, 5'd16,
                     5'd17, 5'd18, 5'd19),
            1
        );
        run_encryption(
            pack_vec(5'd0, 5'd0, 5'd1),
            pack_key(5'd11, 5'd12, 5'd13,
                     5'd14, 5'd15, 5'd16,
                     5'd17, 5'd18, 5'd19),
            1
        );

        // ------------------------------------------------------------
        // 5. Back-to-back Operations (minimal gap)
        // ------------------------------------------------------------
        run_back_to_back(
            pack_vec(5'd7, 5'd4, 5'd11),
            pack_key(5'd6,  5'd24, 5'd1,
                     5'd13, 5'd16, 5'd10,
                     5'd20, 5'd17, 5'd15)
        );
        run_back_to_back(
            pack_vec(5'd11, 5'd14, 5'd22),
            pack_key(5'd2, 5'd4,  5'd5,
                     5'd9, 5'd2,  5'd1,
                     5'd3, 5'd17, 5'd7)
        );
        run_back_to_back(
            pack_vec(5'd2, 5'd0, 5'd19),
            pack_key(5'd3, 5'd10, 5'd20,
                     5'd1, 5'd9,  5'd15,
                     5'd8, 5'd7,  5'd17)
        );

        // ------------------------------------------------------------
        // 6. Mid-operation Asynchronous Reset Recovery Test
        // ------------------------------------------------------------
        @(negedge clk);
        plaintext = pack_vec(5'd15, 5'd21, 5'd4);
        key       = pack_key(5'd5, 5'd8, 5'd12,
                             5'd3, 5'd7, 5'd19,
                             5'd9, 5'd2, 5'd14);
        start     = 1'b1;
        @(posedge clk);
        @(negedge clk);
        start     = 1'b0;

        // Assert reset asynchronously mid-encryption
        @(posedge clk);
        #2;
        reset = 1'b1;
        #1;
        if (ciphertext !== 15'd0) begin
            $display("FAIL: Mid-op async reset did not clear ciphertext immediately (got %b)", ciphertext);
            errors = errors + 1;
        end
        @(posedge clk);
        #1;
        if (ciphertext !== 15'd0 || done !== 1'b0) begin
            $display("FAIL: Outputs not cleared during mid-op reset (ciphertext=%b, done=%b)", ciphertext, done);
            errors = errors + 1;
        end
        @(negedge clk);
        reset = 1'b0;

        // Confirm normal operation resumes cleanly after mid-op reset
        run_encryption(
            pack_vec(5'd2, 5'd0, 5'd19),
            pack_key(5'd3, 5'd10, 5'd20,
                     5'd1, 5'd9,  5'd15,
                     5'd8, 5'd7,  5'd17),
            1
        );

        // ------------------------------------------------------------
        // 7. Pseudo-Random Stress Tests (values 0..25)
        // ------------------------------------------------------------
        for (i = 0; i < 50; i = i + 1) begin : rand_loop
            reg [4:0] rp0, rp1, rp2;
            reg [4:0] rk00, rk01, rk02, rk10, rk11, rk12, rk20, rk21, rk22;
            rp0  = ($random(seed) & 32'h7FFF_FFFF) % 26;
            rp1  = ($random(seed) & 32'h7FFF_FFFF) % 26;
            rp2  = ($random(seed) & 32'h7FFF_FFFF) % 26;
            rk00 = ($random(seed) & 32'h7FFF_FFFF) % 26;
            rk01 = ($random(seed) & 32'h7FFF_FFFF) % 26;
            rk02 = ($random(seed) & 32'h7FFF_FFFF) % 26;
            rk10 = ($random(seed) & 32'h7FFF_FFFF) % 26;
            rk11 = ($random(seed) & 32'h7FFF_FFFF) % 26;
            rk12 = ($random(seed) & 32'h7FFF_FFFF) % 26;
            rk20 = ($random(seed) & 32'h7FFF_FFFF) % 26;
            rk21 = ($random(seed) & 32'h7FFF_FFFF) % 26;
            rk22 = ($random(seed) & 32'h7FFF_FFFF) % 26;

            run_encryption(
                pack_vec(rp0, rp1, rp2),
                pack_key(rk00, rk01, rk02,
                         rk10, rk11, rk12,
                         rk20, rk21, rk22),
                (i % 2)
            );
        end

        // ------------------------------------------------------------
        // Final Summary
        // ------------------------------------------------------------
        if (errors == 0) begin
            $display("PASS");
        end else begin
            $display("FAIL: %0d errors", errors);
        end
        $finish;
    end

endmodule
