`timescale 1ns/1ps

module tb;

    // -------------------------------------------------------------------------
    // Parameters / State Encodings
    // -------------------------------------------------------------------------
    localparam [2:0] HEAT_LOW  = 3'b000;
    localparam [2:0] HEAT_MED  = 3'b001;
    localparam [2:0] HEAT_FULL = 3'b010;
    localparam [2:0] AMBIENT   = 3'b011;
    localparam [2:0] COOL_LOW  = 3'b100;
    localparam [2:0] COOL_MED  = 3'b101;
    localparam [2:0] COOL_FULL = 3'b110;

    // -------------------------------------------------------------------------
    // DUT Signals
    // -------------------------------------------------------------------------
    reg  [5:0] i_temp_feedback;
    reg        i_fan_on;
    reg        i_enable;
    reg        i_fault;
    reg        i_clr;
    reg        i_clk;
    reg        i_rst;

    wire       o_heater_full;
    wire       o_heater_medium;
    wire       o_heater_low;
    wire       o_aircon_full;
    wire       o_aircon_medium;
    wire       o_aircon_low;
    wire       o_fan;
    wire [2:0] o_state;

    wire [6:0] actual_ctrl = {
        o_heater_full,
        o_heater_medium,
        o_heater_low,
        o_aircon_full,
        o_aircon_medium,
        o_aircon_low,
        o_fan
    };

    integer errors = 0;
    integer seed   = 32'h20250401;
    integer i;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    thermostat dut (
        .i_temp_feedback (i_temp_feedback),
        .i_fan_on        (i_fan_on),
        .i_enable        (i_enable),
        .i_fault         (i_fault),
        .i_clr           (i_clr),
        .i_clk           (i_clk),
        .i_rst           (i_rst),
        .o_heater_full   (o_heater_full),
        .o_heater_medium (o_heater_medium),
        .o_heater_low    (o_heater_low),
        .o_aircon_full   (o_aircon_full),
        .o_aircon_medium (o_aircon_medium),
        .o_aircon_low    (o_aircon_low),
        .o_fan           (o_fan),
        .o_state         (o_state)
    );

    // -------------------------------------------------------------------------
    // Clock Generation (10 ns period)
    // -------------------------------------------------------------------------
    initial begin
        i_clk = 1'b0;
        forever #5 i_clk = ~i_clk;
    end

    // -------------------------------------------------------------------------
    // Helper Functions
    // -------------------------------------------------------------------------
    function [2:0] calc_next_state;
        input [5:0] fb;
        begin
            if (fb[5])      calc_next_state = HEAT_FULL;
            else if (fb[4]) calc_next_state = HEAT_MED;
            else if (fb[3]) calc_next_state = HEAT_LOW;
            else if (fb[0]) calc_next_state = COOL_FULL;
            else if (fb[1]) calc_next_state = COOL_MED;
            else if (fb[2]) calc_next_state = COOL_LOW;
            else            calc_next_state = AMBIENT;
        end
    endfunction

    function [6:0] expected_ctrl_for_state;
        input [2:0] st;
        input       fan_on;
        begin
            case (st)
                HEAT_FULL: expected_ctrl_for_state = 7'b100_000_1;
                HEAT_MED:  expected_ctrl_for_state = 7'b010_000_1;
                HEAT_LOW:  expected_ctrl_for_state = 7'b001_000_1;
                COOL_FULL: expected_ctrl_for_state = 7'b000_100_1;
                COOL_MED:  expected_ctrl_for_state = 7'b000_010_1;
                COOL_LOW:  expected_ctrl_for_state = 7'b000_001_1;
                AMBIENT:   expected_ctrl_for_state = {6'b000_000, fan_on};
                default:   expected_ctrl_for_state = 7'b000_000_0;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Checking Tasks
    // -------------------------------------------------------------------------
    task check_outputs;
        input [2:0]        exp_state;
        input              check_state;
        input [6:0]        exp_ctrl;
        input [8*64-1:0]   label;
        begin
            if (check_state && (o_state !== exp_state)) begin
                $display("FAIL [%0s] @ %0t: o_state mismatch. Expected %3b, got %3b",
                         label, $time, exp_state, o_state);
                errors = errors + 1;
            end
            if (actual_ctrl !== exp_ctrl) begin
                $display("FAIL [%0s] @ %0t: ctrl outputs mismatch {hf,hm,hl,af,am,al,fan}. Expected %7b, got %7b (state=%3b)",
                         label, $time, exp_ctrl, actual_ctrl, o_state);
                errors = errors + 1;
            end
        end
    endtask

    task step_and_check;
        input [5:0]        fb;
        input              fan_on;
        input              en;
        input              fault;
        input              clr;
        input [2:0]        exp_state;
        input              check_state;
        input [6:0]        exp_ctrl;
        input [8*64-1:0]   label;
        begin
            @(negedge i_clk);
            i_temp_feedback = fb;
            i_fan_on        = fan_on;
            i_enable        = en;
            i_fault         = fault;
            i_clr           = clr;
            @(posedge i_clk);
            #1;
            check_outputs(exp_state, check_state, exp_ctrl, label);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    reg [2:0] prev_state;
    reg       fault_latched;
    reg [5:0] rand_fb;
    reg       rand_fan;
    reg       rand_en;
    reg       rand_fault;
    reg       rand_clr;
    reg [2:0] cold_bits;
    reg [2:0] hot_bits;
    integer   mode;

    initial begin
        // Initialize inputs
        i_temp_feedback = 6'b000000;
        i_fan_on        = 1'b0;
        i_enable        = 1'b0;
        i_fault         = 1'b0;
        i_clr           = 1'b0;
        i_rst           = 1'b0;

        // ---------------------------------------------------------------------
        // Test 1: Initial Asynchronous Reset
        // ---------------------------------------------------------------------
        #2;
        check_outputs(AMBIENT, 1'b1, 7'b000_000_0, "Init async reset");

        // Hold reset across clock edge even with active inputs
        @(negedge i_clk);
        i_temp_feedback = 6'b100000; // full cold
        i_fan_on        = 1'b1;
        i_enable        = 1'b1;
        @(posedge i_clk);
        #1;
        check_outputs(AMBIENT, 1'b1, 7'b000_000_0, "Reset overrides clock/inputs");

        // Release reset cleanly
        @(negedge i_clk);
        i_rst           = 1'b1;
        i_temp_feedback = 6'b000000;
        i_fan_on        = 1'b0;
        @(posedge i_clk);
        #1;
        check_outputs(AMBIENT, 1'b1, 7'b000_000_0, "Post-reset AMBIENT fan=0");

        // ---------------------------------------------------------------------
        // Test 2: All 7 States + Fan Control (i_fan_on = 0 and 1)
        // ---------------------------------------------------------------------
        step_and_check(6'b000000, 1'b1, 1'b1, 1'b0, 1'b0, AMBIENT,   1'b1, 7'b000_000_1, "AMBIENT fan=1");
        step_and_check(6'b000000, 1'b0, 1'b1, 1'b0, 1'b0, AMBIENT,   1'b1, 7'b000_000_0, "AMBIENT fan=0");

        step_and_check(6'b001000, 1'b0, 1'b1, 1'b0, 1'b0, HEAT_LOW,  1'b1, 7'b001_000_1, "HEAT_LOW fan_on=0");
        step_and_check(6'b001000, 1'b1, 1'b1, 1'b0, 1'b0, HEAT_LOW,  1'b1, 7'b001_000_1, "HEAT_LOW fan_on=1");

        step_and_check(6'b010000, 1'b0, 1'b1, 1'b0, 1'b0, HEAT_MED,  1'b1, 7'b010_000_1, "HEAT_MED fan_on=0");
        step_and_check(6'b010000, 1'b1, 1'b1, 1'b0, 1'b0, HEAT_MED,  1'b1, 7'b010_000_1, "HEAT_MED fan_on=1");

        step_and_check(6'b100000, 1'b0, 1'b1, 1'b0, 1'b0, HEAT_FULL, 1'b1, 7'b100_000_1, "HEAT_FULL fan_on=0");
        step_and_check(6'b100000, 1'b1, 1'b1, 1'b0, 1'b0, HEAT_FULL, 1'b1, 7'b100_000_1, "HEAT_FULL fan_on=1");

        step_and_check(6'b000100, 1'b0, 1'b1, 1'b0, 1'b0, COOL_LOW,  1'b1, 7'b000_001_1, "COOL_LOW fan_on=0");
        step_and_check(6'b000100, 1'b1, 1'b1, 1'b0, 1'b0, COOL_LOW,  1'b1, 7'b000_001_1, "COOL_LOW fan_on=1");

        step_and_check(6'b000010, 1'b0, 1'b1, 1'b0, 1'b0, COOL_MED,  1'b1, 7'b000_010_1, "COOL_MED fan_on=0");
        step_and_check(6'b000010, 1'b1, 1'b1, 1'b0, 1'b0, COOL_MED,  1'b1, 7'b000_010_1, "COOL_MED fan_on=1");

        step_and_check(6'b000001, 1'b0, 1'b1, 1'b0, 1'b0, COOL_FULL, 1'b1, 7'b000_100_1, "COOL_FULL fan_on=0");
        step_and_check(6'b000001, 1'b1, 1'b1, 1'b0, 1'b0, COOL_FULL, 1'b1, 7'b000_100_1, "COOL_FULL fan_on=1");

        // ---------------------------------------------------------------------
        // Test 3: Priority Encoding (All valid cold & hot combinations)
        // ---------------------------------------------------------------------
        for (i = 1; i < 8; i = i + 1) begin
            cold_bits = i[2:0];
            step_and_check({cold_bits, 3'b000}, 1'b0, 1'b1, 1'b0, 1'b0,
                           calc_next_state({cold_bits, 3'b000}), 1'b1,
                           expected_ctrl_for_state(calc_next_state({cold_bits, 3'b000}), 1'b0),
                           "Cold priority sweep");
        end

        for (i = 1; i < 8; i = i + 1) begin
            hot_bits = i[2:0];
            step_and_check({3'b000, hot_bits}, 1'b0, 1'b1, 1'b0, 1'b0,
                           calc_next_state({3'b000, hot_bits}), 1'b1,
                           expected_ctrl_for_state(calc_next_state({3'b000, hot_bits}), 1'b0),
                           "Hot priority sweep");
        end

        // ---------------------------------------------------------------------
        // Test 4: Direct Heating <-> Cooling <-> Ambient Transitions
        // ---------------------------------------------------------------------
        step_and_check(6'b100000, 1'b0, 1'b1, 1'b0, 1'b0, HEAT_FULL, 1'b1, 7'b100_000_1, "Trans -> HEAT_FULL");
        step_and_check(6'b000001, 1'b0, 1'b1, 1'b0, 1'b0, COOL_FULL, 1'b1, 7'b000_100_1, "Trans -> COOL_FULL");
        step_and_check(6'b001000, 1'b0, 1'b1, 1'b0, 1'b0, HEAT_LOW,  1'b1, 7'b001_000_1, "Trans -> HEAT_LOW");
        step_and_check(6'b000010, 1'b0, 1'b1, 1'b0, 1'b0, COOL_MED,  1'b1, 7'b000_010_1, "Trans -> COOL_MED");
        step_and_check(6'b010000, 1'b0, 1'b1, 1'b0, 1'b0, HEAT_MED,  1'b1, 7'b010_000_1, "Trans -> HEAT_MED");
        step_and_check(6'b000100, 1'b0, 1'b1, 1'b0, 1'b0, COOL_LOW,  1'b1, 7'b000_001_1, "Trans -> COOL_LOW");
        step_and_check(6'b000000, 1'b0, 1'b1, 1'b0, 1'b0, AMBIENT,   1'b1, 7'b000_000_0, "Trans -> AMBIENT");

        // ---------------------------------------------------------------------
        // Test 5: Asynchronous Reset Mid-Operation (from HEAT_FULL & COOL_FULL)
        // ---------------------------------------------------------------------
        step_and_check(6'b100000, 1'b1, 1'b1, 1'b0, 1'b0, HEAT_FULL, 1'b1, 7'b100_000_1, "Pre-async-rst HEAT_FULL");
        #2; // Between posedge and negedge (no clock edge!)
        i_rst = 1'b0;
        #1;
        check_outputs(AMBIENT, 1'b1, 7'b000_000_0, "Async reset mid-cycle from HEAT_FULL");

        @(negedge i_clk);
        i_rst           = 1'b1;
        i_temp_feedback = 6'b000001;
        @(posedge i_clk);
        #1;
        check_outputs(COOL_FULL, 1'b1, 7'b000_100_1, "Pre-async-rst COOL_FULL");
        #2;
        i_rst = 1'b0;
        #1;
        check_outputs(AMBIENT, 1'b1, 7'b000_000_0, "Async reset mid-cycle from COOL_FULL");

        @(negedge i_clk);
        i_rst           = 1'b1;
        i_temp_feedback = 6'b000000;
        i_fan_on        = 1'b0;
        @(posedge i_clk);
        #1;
        check_outputs(AMBIENT, 1'b1, 7'b000_000_0, "Recover from async reset");

        // ---------------------------------------------------------------------
        // Test 6: Enable / Disable Control (i_enable = 0)
        // ---------------------------------------------------------------------
        step_and_check(6'b100000, 1'b1, 1'b1, 1'b0, 1'b0, HEAT_FULL, 1'b1, 7'b100_000_1, "Enable=1 HEAT_FULL");
        // Disable: outputs must go to 0 (even with fan_on=1 and cold feedback)
        step_and_check(6'b100000, 1'b1, 1'b0, 1'b0, 1'b0, AMBIENT,   1'b0, 7'b000_000_0, "Disable=0 forces outputs=0");
        // Change feedback while disabled: outputs must remain 0
        step_and_check(6'b000001, 1'b1, 1'b0, 1'b0, 1'b0, AMBIENT,   1'b0, 7'b000_000_0, "Disable=0 ignores hot feedback");
        // Re-enable with ambient feedback
        step_and_check(6'b000000, 1'b0, 1'b1, 1'b0, 1'b0, AMBIENT,   1'b1, 7'b000_000_0, "Re-enable to AMBIENT");
        // Re-enable into cooling
        step_and_check(6'b000001, 1'b0, 1'b1, 1'b0, 1'b0, COOL_FULL, 1'b1, 7'b000_100_1, "Re-enable to COOL_FULL");

        // ---------------------------------------------------------------------
        // Test 7: Fault Latching, Priority Over Enable/Feedback, and Clear
        // ---------------------------------------------------------------------
        step_and_check(6'b000010, 1'b1, 1'b1, 1'b0, 1'b0, COOL_MED,  1'b1, 7'b000_010_1, "Enter COOL_MED before fault");
        // Assert fault
        step_and_check(6'b100000, 1'b1, 1'b1, 1'b1, 1'b0, AMBIENT,   1'b0, 7'b000_000_0, "Fault=1 forces outputs=0");
        // Deassert fault without i_clr: fault must remain latched
        step_and_check(6'b100000, 1'b1, 1'b1, 1'b0, 1'b0, AMBIENT,   1'b0, 7'b000_000_0, "Fault latched (cold fb)");
        step_and_check(6'b000001, 1'b1, 1'b1, 1'b0, 1'b0, AMBIENT,   1'b0, 7'b000_000_0, "Fault latched (hot fb)");
        // Assert i_fault and i_clr together: fault still overrides
        step_and_check(6'b100000, 1'b1, 1'b1, 1'b1, 1'b1, AMBIENT,   1'b0, 7'b000_000_0, "Fault=1 overrides Clr=1");
        // Clear fault with i_fault=0, i_clr=1 while cold feedback present -> must move to AMBIENT
        step_and_check(6'b100000, 1'b0, 1'b1, 1'b0, 1'b1, AMBIENT,   1'b1, 7'b000_000_0, "Clr=1 returns to AMBIENT");
        // Deassert i_clr: normal operation resumes on next rising clock edge
        step_and_check(6'b100000, 1'b0, 1'b1, 1'b0, 1'b0, HEAT_FULL, 1'b1, 7'b100_000_1, "Resume normal -> HEAT_FULL");

        // Test reset while fault is latched
        step_and_check(6'b000001, 1'b1, 1'b1, 1'b1, 1'b0, AMBIENT,   1'b0, 7'b000_000_0, "Fault=1 before reset");
        step_and_check(6'b000001, 1'b1, 1'b1, 1'b0, 1'b0, AMBIENT,   1'b0, 7'b000_000_0, "Fault latched before reset");
        #2;
        i_rst = 1'b0;
        #1;
        check_outputs(AMBIENT, 1'b1, 7'b000_000_0, "Async reset clears latched fault");
        @(negedge i_clk);
        i_rst           = 1'b1;
        i_temp_feedback = 6'b010000;
        i_fan_on        = 1'b0;
        @(posedge i_clk);
        #1;
        check_outputs(HEAT_MED, 1'b1, 7'b010_000_1, "Normal op after reset cleared fault");

        // ---------------------------------------------------------------------
        // Test 8: Constrained Random Stress Test (200 Cycles)
        // ---------------------------------------------------------------------
        step_and_check(6'b000000, 1'b0, 1'b1, 1'b0, 1'b0, AMBIENT, 1'b1, 7'b000_000_0, "Pre-random AMBIENT");
        prev_state    = AMBIENT;
        fault_latched = 1'b0;

        for (i = 0; i < 200; i = i + 1) begin
            // Generate valid mutually exclusive cold/hot feedback
            mode = ($random(seed) & 32'h7FFFFFFF) % 3;
            if (mode == 0) begin
                rand_fb = 6'b000000;
            end else if (mode == 1) begin
                rand_fb = {($random(seed) & 3'b111), 3'b000};
            end else begin
                rand_fb = {3'b000, ($random(seed) & 3'b111)};
            end

            rand_fan   = $random(seed) & 1'b1;
            rand_en    = (($random(seed) & 32'h7FFFFFFF) % 10 != 0); // 90% enabled
            rand_fault = (($random(seed) & 32'h7FFFFFFF) % 25 == 0); // 4% fault
            rand_clr   = (fault_latched && !rand_fault && ((($random(seed) & 32'h7FFFFFFF) % 3) == 0));

            // Keep fan_on=0 on exact clear cycle to avoid ambiguity on clear-edge fan output
            if (rand_clr) rand_fan = 1'b0;

            @(negedge i_clk);
            i_temp_feedback = rand_fb;
            i_fan_on        = rand_fan;
            i_enable        = rand_en;
            i_fault         = rand_fault;
            i_clr           = rand_clr;

            @(posedge i_clk);
            #1;

            if (rand_fault) begin
                fault_latched = 1'b1;
                check_outputs(AMBIENT, 1'b0, 7'b000_000_0, "Random fault active");
            end else if (fault_latched) begin
                if (rand_clr) begin
                    fault_latched = 1'b0;
                    prev_state    = AMBIENT;
                    check_outputs(AMBIENT, 1'b1, 7'b000_000_0, "Random fault cleared");
                end else begin
                    check_outputs(AMBIENT, 1'b0, 7'b000_000_0, "Random fault held");
                end
            end else if (!rand_en) begin
                check_outputs(AMBIENT, 1'b0, 7'b000_000_0, "Random disabled");
                prev_state = o_state;
            end else begin
                prev_state = calc_next_state(rand_fb);
                check_outputs(prev_state, 1'b1,
                              expected_ctrl_for_state(prev_state, rand_fan),
                              "Random normal");
            end
        end

        // ---------------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------------
        if (errors == 0) begin
            $display("PASS");
        end else begin
            $display("FAIL: %0d errors", errors);
        end
        $finish;
    end

endmodule
