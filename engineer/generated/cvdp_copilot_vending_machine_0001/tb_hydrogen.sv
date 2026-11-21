`timescale 1ns/1ps

module tb;

    reg        clk;
    reg        rst;
    reg        item_button;
    reg  [2:0] item_selected;
    reg  [3:0] coin_input;
    reg        cancel;

    wire       dispense_item;
    wire       return_change;
    wire [4:0] item_price;
    wire [4:0] change_amount;
    wire [2:0] dispense_item_id;
    wire       error;
    wire       return_money;

    integer errors = 0;

    // Pulse counters for active monitoring on negedge clk
    reg        monitor_en;
    integer    cnt_dispense;
    integer    cnt_return_change;
    integer    cnt_error;
    integer    cnt_return_money;
    reg  [2:0] captured_dispense_id;
    reg  [4:0] captured_change_amount;

    // Stored prices observed from the DUT for valid items 1..4
    reg  [4:0] item_prices [1:4];

    vending_machine dut (
        .clk              (clk),
        .rst              (rst),
        .item_button      (item_button),
        .item_selected    (item_selected),
        .coin_input       (coin_input),
        .cancel           (cancel),
        .dispense_item    (dispense_item),
        .return_change    (return_change),
        .item_price       (item_price),
        .change_amount    (change_amount),
        .dispense_item_id (dispense_item_id),
        .error            (error),
        .return_money     (return_money)
    );

    // 10ns clock period
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Global timeout watchdog
    initial begin
        #50000;
        $display("FAIL: Simulation timeout");
        errors = errors + 1;
        $display("FAIL: %0d errors", errors);
        $finish;
    end

    // Sample outputs safely in the middle of each cycle
    always @(negedge clk) begin
        if (monitor_en && !rst) begin
            if (dispense_item === 1'b1) begin
                cnt_dispense = cnt_dispense + 1;
                captured_dispense_id = dispense_item_id;
            end
            if (return_change === 1'b1) begin
                cnt_return_change = cnt_return_change + 1;
                captured_change_amount = change_amount;
            end
            if (error === 1'b1) begin
                cnt_error = cnt_error + 1;
            end
            if (return_money === 1'b1) begin
                cnt_return_money = cnt_return_money + 1;
            end
        end
    end

    task clear_counters;
        begin
            cnt_dispense           = 0;
            cnt_return_change      = 0;
            cnt_error              = 0;
            cnt_return_money       = 0;
            captured_dispense_id   = 3'b000;
            captured_change_amount = 5'd0;
        end
    endtask

    task check_all_outputs_zero;
        input [255:0] ctx;
        begin
            if (dispense_item !== 1'b0) begin
                $display("FAIL: %0s - expected dispense_item=0, got %b", ctx, dispense_item);
                errors = errors + 1;
            end
            if (return_change !== 1'b0) begin
                $display("FAIL: %0s - expected return_change=0, got %b", ctx, return_change);
                errors = errors + 1;
            end
            if (item_price !== 5'd0) begin
                $display("FAIL: %0s - expected item_price=0, got %0d", ctx, item_price);
                errors = errors + 1;
            end
            if (change_amount !== 5'd0) begin
                $display("FAIL: %0s - expected change_amount=0, got %0d", ctx, change_amount);
                errors = errors + 1;
            end
            if (dispense_item_id !== 3'b000) begin
                $display("FAIL: %0s - expected dispense_item_id=0, got %b", ctx, dispense_item_id);
                errors = errors + 1;
            end
            if (error !== 1'b0) begin
                $display("FAIL: %0s - expected error=0, got %b", ctx, error);
                errors = errors + 1;
            end
            if (return_money !== 1'b0) begin
                $display("FAIL: %0s - expected return_money=0, got %b", ctx, return_money);
                errors = errors + 1;
            end
        end
    endtask

    task wait_cycles;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    task apply_reset;
        begin
            monitor_en    = 1'b0;
            item_button   = 1'b0;
            item_selected = 3'b000;
            coin_input    = 4'd0;
            cancel        = 1'b0;
            rst           = 1'b1;
            #2;
            check_all_outputs_zero("async reset assertion");
            @(posedge clk);
            #1;
            check_all_outputs_zero("reset held across posedge");
            rst = 1'b0;
            @(posedge clk);
            #1;
            clear_counters();
            monitor_en = 1'b1;
        end
    endtask

    // Press item_button for 1 cycle and wait for valid item_price
    task select_valid_item;
        input  [2:0] id;
        output [4:0] observed_price;
        integer cyc;
        begin
            @(posedge clk);
            #1;
            item_button   = 1'b1;
            item_selected = id;

            @(posedge clk);
            #1;
            item_button = 1'b0;

            observed_price = 5'd0;
            for (cyc = 0; cyc < 6; cyc = cyc + 1) begin
                @(negedge clk);
                if (item_price > 5'd0 && observed_price == 5'd0) begin
                    observed_price = item_price;
                end
                @(posedge clk);
                #1;
            end

            if (observed_price == 5'd0) begin
                $display("FAIL: select_valid_item(%0d) - item_price remained 0", id);
                errors = errors + 1;
            end
        end
    endtask

    // Insert a single coin for 1 clock cycle followed by 1 idle cycle
    task insert_single_coin;
        input [3:0] coin;
        begin
            @(posedge clk);
            #1;
            coin_input = coin;
            @(posedge clk);
            #1;
            coin_input = 4'd0;
        end
    endtask

    // Complete an exact-payment transaction for a given item ID
    task run_exact_transaction;
        input [2:0] id;
        output [4:0] out_price;
        reg [4:0] rem;
        reg [3:0] coin;
        integer cyc;
        begin
            clear_counters();
            select_valid_item(id, out_price);

            if (out_price > 5'd0) begin
                rem = out_price;
                while (rem > 5'd0) begin
                    if (rem >= 5'd10)      coin = 4'd10;
                    else if (rem >= 5'd5)  coin = 4'd5;
                    else if (rem >= 5'd2)  coin = 4'd2;
                    else                   coin = 4'd1;
                    insert_single_coin(coin);
                    rem = rem - coin;
                end
            end

            // Wait for dispense and ensure settle back to IDLE
            for (cyc = 0; cyc < 6; cyc = cyc + 1) begin
                @(posedge clk);
                #1;
            end

            item_selected = 3'b000;

            if (cnt_dispense !== 1) begin
                $display("FAIL: Exact payment item %0d - expected dispense_item pulse count 1, got %0d", id, cnt_dispense);
                errors = errors + 1;
            end else if (captured_dispense_id !== id) begin
                $display("FAIL: Exact payment item %0d - expected dispense_item_id=%0d, got %0d", id, id, captured_dispense_id);
                errors = errors + 1;
            end
            if (cnt_return_change !== 0) begin
                $display("FAIL: Exact payment item %0d - expected return_change count 0, got %0d", id, cnt_return_change);
                errors = errors + 1;
            end
            if (cnt_error !== 0) begin
                $display("FAIL: Exact payment item %0d - expected error count 0, got %0d", id, cnt_error);
                errors = errors + 1;
            end
            if (cnt_return_money !== 0) begin
                $display("FAIL: Exact payment item %0d - expected return_money count 0, got %0d", id, cnt_return_money);
                errors = errors + 1;
            end
        end
    endtask

    // Complete an overpayment transaction using a specified final coin
    task run_overpay_transaction;
        input [2:0] id;
        input [3:0] final_coin;
        reg [4:0] price;
        reg [4:0] paid;
        reg [4:0] rem;
        reg [4:0] expected_change;
        reg [3:0] coin;
        integer cyc;
        begin
            clear_counters();
            select_valid_item(id, price);

            paid = 5'd0;
            if (price > 5'd0) begin
                // Insert coins until remaining amount is strictly less than final_coin
                while ((price - paid) >= final_coin) begin
                    rem = price - paid;
                    if (rem >= 5'd10 && (price - (paid + 5'd10)) >= 5'd1)      coin = 4'd10;
                    else if (rem >= 5'd5 && (price - (paid + 5'd5)) >= 5'd1)  coin = 4'd5;
                    else if (rem >= 5'd2 && (price - (paid + 5'd2)) >= 5'd1)  coin = 4'd2;
                    else                                                       coin = 4'd1;
                    insert_single_coin(coin);
                    paid = paid + coin;
                end
                // Insert final coin to exceed price
                insert_single_coin(final_coin);
                paid = paid + final_coin;
                expected_change = paid - price;
            end else begin
                expected_change = 5'd0;
            end

            for (cyc = 0; cyc < 8; cyc = cyc + 1) begin
                @(posedge clk);
                #1;
            end

            item_selected = 3'b000;

            if (cnt_dispense !== 1) begin
                $display("FAIL: Overpay item %0d (coin %0d) - expected dispense_item count 1, got %0d", id, final_coin, cnt_dispense);
                errors = errors + 1;
            end else if (captured_dispense_id !== id) begin
                $display("FAIL: Overpay item %0d - expected dispense_item_id=%0d, got %0d", id, id, captured_dispense_id);
                errors = errors + 1;
            end
            if (cnt_return_change !== 1) begin
                $display("FAIL: Overpay item %0d (coin %0d) - expected return_change count 1, got %0d", id, final_coin, cnt_return_change);
                errors = errors + 1;
            end else if (captured_change_amount !== expected_change) begin
                $display("FAIL: Overpay item %0d (coin %0d) - expected change_amount=%0d, got %0d", id, final_coin, expected_change, captured_change_amount);
                errors = errors + 1;
            end
            if (cnt_error !== 0) begin
                $display("FAIL: Overpay item %0d (coin %0d) - expected error count 0, got %0d", id, final_coin, cnt_error);
                errors = errors + 1;
            end
            if (cnt_return_money !== 0) begin
                $display("FAIL: Overpay item %0d (coin %0d) - expected return_money count 0, got %0d", id, final_coin, cnt_return_money);
                errors = errors + 1;
            end
        end
    endtask

    integer i;
    reg [2:0] max_item_id;
    reg [4:0] max_item_price;
    reg [4:0] tmp_price;

    initial begin
        monitor_en    = 1'b0;
        rst           = 1'b0;
        item_button   = 1'b0;
        item_selected = 3'b000;
        coin_input    = 4'd0;
        cancel        = 1'b0;
        clear_counters();

        // -----------------------------------------------------------------
        // Test 1: Asynchronous Reset at Startup
        // -----------------------------------------------------------------
        apply_reset();

        // -----------------------------------------------------------------
        // Test 2: Exact Payment for All 4 Valid Items (3'b001 .. 3'b100)
        // -----------------------------------------------------------------
        max_item_id    = 3'b001;
        max_item_price = 5'd0;
        for (i = 1; i <= 4; i = i + 1) begin
            run_exact_transaction(i[2:0], item_prices[i]);
            if (item_prices[i] > max_item_price) begin
                max_item_price = item_prices[i];
                max_item_id    = i[2:0];
            end
        end

        // -----------------------------------------------------------------
        // Test 3: Overpayment & Change Return (testing 2, 5, 10 coin types)
        // -----------------------------------------------------------------
        run_overpay_transaction(3'b001, 4'd2);
        run_overpay_transaction(3'b010, 4'd5);
        run_overpay_transaction(3'b011, 4'd10);
        run_overpay_transaction(3'b100, 4'd10);

        // -----------------------------------------------------------------
        // Test 4: Invalid Item Selection (3'b101, 3'b111) & Recovery
        // -----------------------------------------------------------------
        clear_counters();
        @(posedge clk); #1;
        item_button   = 1'b1;
        item_selected = 3'b101;
        @(posedge clk); #1;
        item_button   = 1'b0;
        wait_cycles(6);
        item_selected = 3'b000;
        if (cnt_error !== 1) begin
            $display("FAIL: Invalid item 3'b101 - expected error count 1, got %0d", cnt_error);
            errors = errors + 1;
        end
        if (cnt_dispense !== 0 || cnt_return_change !== 0) begin
            $display("FAIL: Invalid item 3'b101 - unexpected dispense(%0d)/change(%0d)", cnt_dispense, cnt_return_change);
            errors = errors + 1;
        end

        clear_counters();
        @(posedge clk); #1;
        item_button   = 1'b1;
        item_selected = 3'b111;
        @(posedge clk); #1;
        item_button   = 1'b0;
        wait_cycles(6);
        item_selected = 3'b000;
        if (cnt_error !== 1) begin
            $display("FAIL: Invalid item 3'b111 - expected error count 1, got %0d", cnt_error);
            errors = errors + 1;
        end
        // Verify clean recovery with a normal transaction
        run_exact_transaction(3'b001, tmp_price);

        // -----------------------------------------------------------------
        // Test 5: Invalid Coin Insertion (with 0 coins and with >0 coins)
        // -----------------------------------------------------------------
        // 5a: Invalid coin immediately after item selection
        clear_counters();
        select_valid_item(max_item_id, tmp_price);
        insert_single_coin(4'd3);
        wait_cycles(6);
        item_selected = 3'b000;
        if (cnt_error !== 1) begin
            $display("FAIL: Invalid coin 3 (0 prior coins) - expected error count 1, got %0d", cnt_error);
            errors = errors + 1;
        end
        if (cnt_dispense !== 0 || cnt_return_change !== 0) begin
            $display("FAIL: Invalid coin 3 - unexpected dispense/change");
            errors = errors + 1;
        end

        // 5b: Invalid coin after inserting a valid coin (must return money)
        if (max_item_price > 5'd1) begin
            clear_counters();
            select_valid_item(max_item_id, tmp_price);
            insert_single_coin(4'd1);
            insert_single_coin(4'd7);
            wait_cycles(6);
            item_selected = 3'b000;
            if (cnt_error !== 1) begin
                $display("FAIL: Invalid coin 7 (after 1 coin) - expected error count 1, got %0d", cnt_error);
                errors = errors + 1;
            end
            if (cnt_return_money !== 1) begin
                $display("FAIL: Invalid coin 7 (after 1 coin) - expected return_money count 1, got %0d", cnt_return_money);
                errors = errors + 1;
            end
            if (cnt_dispense !== 0 || cnt_return_change !== 0) begin
                $display("FAIL: Invalid coin 7 - unexpected dispense/change");
                errors = errors + 1;
            end
            // Verify accumulated coins were cleared
            run_exact_transaction(max_item_id, tmp_price);
        end

        // -----------------------------------------------------------------
        // Test 6: Inserting Coins in IDLE Without Item Selection
        // -----------------------------------------------------------------
        clear_counters();
        insert_single_coin(4'd5);
        wait_cycles(6);
        if (cnt_error !== 1) begin
            $display("FAIL: Coin 5 in IDLE - expected error count 1, got %0d", cnt_error);
            errors = errors + 1;
        end
        if (cnt_dispense !== 0 || cnt_return_change !== 0) begin
            $display("FAIL: Coin 5 in IDLE - unexpected dispense/change");
            errors = errors + 1;
        end
        // Verify coins did not accumulate in IDLE
        run_exact_transaction(3'b001, tmp_price);

        // -----------------------------------------------------------------
        // Test 7: Cancel Transaction (with 0 coins and with >0 coins)
        // -----------------------------------------------------------------
        // 7a: Cancel with 0 coins inserted
        clear_counters();
        select_valid_item(max_item_id, tmp_price);
        @(posedge clk); #1;
        cancel = 1'b1;
        @(posedge clk); #1;
        cancel = 1'b0;
        wait_cycles(6);
        item_selected = 3'b000;
        if (cnt_error !== 1) begin
            $display("FAIL: Cancel (0 coins) - expected error count 1, got %0d", cnt_error);
            errors = errors + 1;
        end
        if (cnt_dispense !== 0 || cnt_return_change !== 0) begin
            $display("FAIL: Cancel (0 coins) - unexpected dispense/change");
            errors = errors + 1;
        end

        // 7b: Cancel after inserting partial coins
        if (max_item_price > 5'd1) begin
            clear_counters();
            select_valid_item(max_item_id, tmp_price);
            insert_single_coin(4'd1);
            @(posedge clk); #1;
            cancel = 1'b1;
            @(posedge clk); #1;
            cancel = 1'b0;
            wait_cycles(6);
            item_selected = 3'b000;
            if (cnt_error !== 1) begin
                $display("FAIL: Cancel (1 coin) - expected error count 1, got %0d", cnt_error);
                errors = errors + 1;
            end
            if (cnt_return_money !== 1) begin
                $display("FAIL: Cancel (1 coin) - expected return_money count 1, got %0d", cnt_return_money);
                errors = errors + 1;
            end
            if (cnt_dispense !== 0 || cnt_return_change !== 0) begin
                $display("FAIL: Cancel (1 coin) - unexpected dispense/change");
                errors = errors + 1;
            end
            // Ensure coins were cleared after cancel
            run_exact_transaction(max_item_id, tmp_price);
        end

        // -----------------------------------------------------------------
        // Test 8: Rising-Edge Sensitivity of item_button and cancel
        // -----------------------------------------------------------------
        // 8a: Hold item_button=1 across an entire transaction and into IDLE
        clear_counters();
        @(posedge clk); #1;
        item_button   = 1'b1;
        item_selected = 3'b001;
        wait_cycles(5);
        // Pay exact price while keeping item_button held high
        begin : pay_while_held
            reg [4:0] rem_h;
            reg [3:0] coin_h;
            rem_h = item_prices[1];
            while (rem_h > 5'd0) begin
                if (rem_h >= 5'd10)      coin_h = 4'd10;
                else if (rem_h >= 5'd5)  coin_h = 4'd5;
                else if (rem_h >= 5'd2)  coin_h = 4'd2;
                else                     coin_h = 4'd1;
                insert_single_coin(coin_h);
                rem_h = rem_h - coin_h;
            end
        end
        wait_cycles(6);
        item_selected = 3'b000;
        if (cnt_dispense !== 1 || cnt_error !== 0) begin
            $display("FAIL: Held item_button transaction - dispense=%0d error=%0d", cnt_dispense, cnt_error);
            errors = errors + 1;
        end

        // Still holding item_button=1 in IDLE: inserting a coin must trigger error
        // (proving machine did NOT re-enter ITEM_SELECTION without a new rising edge)
        clear_counters();
        item_selected = 3'b010;
        wait_cycles(2);
        insert_single_coin(4'd1);
        wait_cycles(6);
        item_selected = 3'b000;
        if (cnt_error !== 1) begin
            $display("FAIL: Continuous item_button=1 re-triggered selection - expected error=1 on coin in IDLE, got %0d", cnt_error);
            errors = errors + 1;
        end
        item_button = 1'b0;
        wait_cycles(2);

        // 8b: Hold cancel=1 across cancellation and into IDLE
        clear_counters();
        select_valid_item(3'b001, tmp_price);
        @(posedge clk); #1;
        cancel = 1'b1;
        wait_cycles(8);
        item_selected = 3'b000;
        if (cnt_error !== 1) begin
            $display("FAIL: Held cancel=1 - expected exactly 1 error pulse, got %0d", cnt_error);
            errors = errors + 1;
        end
        cancel = 1'b0;
        wait_cycles(2);
        run_exact_transaction(3'b001, tmp_price);

        // -----------------------------------------------------------------
        // Test 9: Asynchronous Reset During Active Transaction
        // -----------------------------------------------------------------
        if (max_item_price > 5'd1) begin
            clear_counters();
            select_valid_item(max_item_id, tmp_price);
            insert_single_coin(4'd1);
            wait_cycles(1);

            // Assert rst asynchronously between clock edges
            monitor_en = 1'b0;
            #2;
            rst = 1'b1;
            #1;
            check_all_outputs_zero("async reset mid-transaction");
            @(posedge clk);
            #1;
            rst           = 1'b0;
            item_selected = 3'b000;
            clear_counters();
            monitor_en    = 1'b1;

            // Verify accumulated coin was cleared by running exact transaction
            run_exact_transaction(max_item_id, tmp_price);
        end

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        if (errors == 0)
            $display("PASS");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
