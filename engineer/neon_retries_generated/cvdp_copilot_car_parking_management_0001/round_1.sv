module car_parking_system #(
    parameter TOTAL_SPACES = 12
) (
    input  logic                            clk,
    input  logic                            reset,
    input  logic                            vehicle_entry_sensor,
    input  logic                            vehicle_exit_sensor,
    output logic [$clog2(TOTAL_SPACES)-1:0] available_spaces,
    output logic [$clog2(TOTAL_SPACES)-1:0] count_car,
    output logic                            led_status,
    output logic [6:0]                      seven_seg_display_available_tens,
    output logic [6:0]                      seven_seg_display_available_units,
    output logic [6:0]                      seven_seg_display_count_tens,
    output logic [6:0]                      seven_seg_display_count_units
);

    localparam int WIDTH = $clog2(TOTAL_SPACES);
    localparam logic [WIDTH-1:0] MAX_SPACES = TOTAL_SPACES;
    localparam logic [WIDTH-1:0] ZERO_VAL   = 0;
    localparam logic [WIDTH-1:0] ONE_VAL    = 1;

    localparam logic [1:0] IDLE  = 2'b00;
    localparam logic [1:0] ENTRY = 2'b01;
    localparam logic [1:0] EXIT  = 2'b10;
    localparam logic [1:0] FULL  = 2'b11;

    logic [1:0]       current_state, next_state;
    logic [WIDTH-1:0] next_available;
    logic [WIDTH-1:0] next_count;

    logic [6:0] avail_ext;
    logic [6:0] count_ext;
    logic [3:0] avail_tens;
    logic [3:0] avail_units;
    logic [3:0] count_tens;
    logic [3:0] count_units;

    function automatic logic [3:0] get_tens(input logic [6:0] val);
        begin
            if (val >= 7'd90)      get_tens = 4'd9;
            else if (val >= 7'd80) get_tens = 4'd8;
            else if (val >= 7'd70) get_tens = 4'd7;
            else if (val >= 7'd60) get_tens = 4'd6;
            else if (val >= 7'd50) get_tens = 4'd5;
            else if (val >= 7'd40) get_tens = 4'd4;
            else if (val >= 7'd30) get_tens = 4'd3;
            else if (val >= 7'd20) get_tens = 4'd2;
            else if (val >= 7'd10) get_tens = 4'd1;
            else                   get_tens = 4'd0;
        end
    endfunction

    function automatic logic [3:0] get_units(input logic [6:0] val);
        logic [6:0] diff;
        begin
            if (val >= 7'd90)      diff = val - 7'd90;
            else if (val >= 7'd80) diff = val - 7'd80;
            else if (val >= 7'd70) diff = val - 7'd70;
            else if (val >= 7'd60) diff = val - 7'd60;
            else if (val >= 7'd50) diff = val - 7'd50;
            else if (val >= 7'd40) diff = val - 7'd40;
            else if (val >= 7'd30) diff = val - 7'd30;
            else if (val >= 7'd20) diff = val - 7'd20;
            else if (val >= 7'd10) diff = val - 7'd10;
            else                   diff = val;
            get_units = diff[3:0];
        end
    endfunction

    function automatic logic [6:0] seg7_encode(input logic [3:0] digit);
        begin
            case (digit)
                4'd0:    seg7_encode = 7'b1111110;
                4'd1:    seg7_encode = 7'b0110000;
                4'd2:    seg7_encode = 7'b1101101;
                4'd3:    seg7_encode = 7'b1111001;
                4'd4:    seg7_encode = 7'b0110011;
                4'd5:    seg7_encode = 7'b1011011;
                4'd6:    seg7_encode = 7'b1011111;
                4'd7:    seg7_encode = 7'b1110000;
                4'd8:    seg7_encode = 7'b1111111;
                4'd9:    seg7_encode = 7'b1111011;
                default: seg7_encode = 7'b0000000;
            endcase
        end
    endfunction

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state    <= IDLE;
            available_spaces <= MAX_SPACES;
            count_car        <= ZERO_VAL;
        end else begin
            current_state    <= next_state;
            available_spaces <= next_available;
            count_car        <= next_count;
        end
    end

    always_comb begin
        next_state     = current_state;
        next_available = available_spaces;
        next_count     = count_car;

        case (current_state)
            IDLE, ENTRY, EXIT: begin
                if (vehicle_entry_sensor && !vehicle_exit_sensor) begin
                    if (available_spaces > ZERO_VAL) begin
                        next_available = available_spaces - ONE_VAL;
                        next_count     = count_car + ONE_VAL;
                        if (available_spaces == ONE_VAL)
                            next_state = FULL;
                        else
                            next_state = ENTRY;
                    end else begin
                        next_state = FULL;
                    end
                end else if (!vehicle_entry_sensor && vehicle_exit_sensor) begin
                    if (count_car > ZERO_VAL) begin
                        next_available = available_spaces + ONE_VAL;
                        next_count     = count_car - ONE_VAL;
                        next_state     = EXIT;
                    end else begin
                        next_state = IDLE;
                    end
                end else if (vehicle_entry_sensor && vehicle_exit_sensor) begin
                    if (available_spaces == ZERO_VAL) begin
                        next_available = available_spaces + ONE_VAL;
                        next_count     = count_car - ONE_VAL;
                        next_state     = EXIT;
                    end else if (count_car == ZERO_VAL) begin
                        next_available = available_spaces - ONE_VAL;
                        next_count     = count_car + ONE_VAL;
                        if (available_spaces == ONE_VAL)
                            next_state = FULL;
                        else
                            next_state = ENTRY;
                    end else begin
                        next_state = IDLE;
                    end
                end else begin
                    if (available_spaces == ZERO_VAL)
                        next_state = FULL;
                    else
                        next_state = IDLE;
                end
            end

            FULL: begin
                if (vehicle_exit_sensor) begin
                    next_available = available_spaces + ONE_VAL;
                    next_count     = count_car - ONE_VAL;
                    next_state     = EXIT;
                end else begin
                    next_state = FULL;
                end
            end

            default: begin
                next_state     = IDLE;
                next_available = MAX_SPACES;
                next_count     = ZERO_VAL;
            end
        endcase
    end

    assign led_status = (available_spaces > ZERO_VAL);

    assign avail_ext   = available_spaces;
    assign count_ext   = count_car;
    assign avail_tens  = get_tens(avail_ext);
    assign avail_units = get_units(avail_ext);
    assign count_tens  = get_tens(count_ext);
    assign count_units = get_units(count_ext);

    assign seven_seg_display_available_tens  = seg7_encode(avail_tens);
    assign seven_seg_display_available_units = seg7_encode(avail_units);
    assign seven_seg_display_count_tens      = seg7_encode(count_tens);
    assign seven_seg_display_count_units     = seg7_encode(count_units);

endmodule
