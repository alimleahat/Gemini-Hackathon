module car_parking_system #(
    parameter TOTAL_SPACES = 12
) (
    input  logic                              clk,
    input  logic                              reset,
    input  logic                              vehicle_entry_sensor,
    input  logic                              vehicle_exit_sensor,
    output logic [$clog2(TOTAL_SPACES+1)-1:0] available_spaces,
    output logic [$clog2(TOTAL_SPACES+1)-1:0] count_car,
    output logic                              led_status,
    output logic [6:0]                        seven_seg_display_available_tens,
    output logic [6:0]                        seven_seg_display_available_units,
    output logic [6:0]                        seven_seg_display_count_tens,
    output logic [6:0]                        seven_seg_display_count_units
);

    localparam int CNT_WIDTH = $clog2(TOTAL_SPACES + 1);
    localparam logic [CNT_WIDTH-1:0] MAX_SPACES = TOTAL_SPACES;
    localparam logic [CNT_WIDTH-1:0] ZERO_VAL   = 0;
    localparam logic [CNT_WIDTH-1:0] ONE_VAL    = 1;

    typedef enum logic [1:0] {
        IDLE             = 2'b00,
        ENTRY_PROCESSING = 2'b01,
        EXIT_PROCESSING  = 2'b10,
        FULL             = 2'b11
    } state_t;

    state_t               current_state;
    state_t               next_state;
    logic [CNT_WIDTH-1:0] next_available_spaces;
    logic [CNT_WIDTH-1:0] next_count_car;

    logic [6:0] avail_ext;
    logic [6:0] count_ext;
    logic [7:0] avail_bcd;
    logic [7:0] count_bcd;

    function automatic logic [7:0] bin_to_bcd(input logic [6:0] val);
        logic [3:0] tens;
        logic [6:0] rem;
        if (val >= 7'd90) begin
            tens = 4'd9;
            rem  = val - 7'd90;
        end else if (val >= 7'd80) begin
            tens = 4'd8;
            rem  = val - 7'd80;
        end else if (val >= 7'd70) begin
            tens = 4'd7;
            rem  = val - 7'd70;
        end else if (val >= 7'd60) begin
            tens = 4'd6;
            rem  = val - 7'd60;
        end else if (val >= 7'd50) begin
            tens = 4'd5;
            rem  = val - 7'd50;
        end else if (val >= 7'd40) begin
            tens = 4'd4;
            rem  = val - 7'd40;
        end else if (val >= 7'd30) begin
            tens = 4'd3;
            rem  = val - 7'd30;
        end else if (val >= 7'd20) begin
            tens = 4'd2;
            rem  = val - 7'd20;
        end else if (val >= 7'd10) begin
            tens = 4'd1;
            rem  = val - 7'd10;
        end else begin
            tens = 4'd0;
            rem  = val;
        end
        bin_to_bcd = {tens, rem[3:0]};
    endfunction

    function automatic logic [6:0] encode_7seg(input logic [3:0] digit);
        case (digit)
            4'd0:    encode_7seg = 7'b1111110;
            4'd1:    encode_7seg = 7'b0110000;
            4'd2:    encode_7seg = 7'b1101101;
            4'd3:    encode_7seg = 7'b1111001;
            4'd4:    encode_7seg = 7'b0110011;
            4'd5:    encode_7seg = 7'b1011011;
            4'd6:    encode_7seg = 7'b1011111;
            4'd7:    encode_7seg = 7'b1110000;
            4'd8:    encode_7seg = 7'b1111111;
            4'd9:    encode_7seg = 7'b1111011;
            default: encode_7seg = 7'b0000000;
        endcase
    endfunction

    always_comb begin
        next_state            = current_state;
        next_available_spaces = available_spaces;
        next_count_car        = count_car;

        case (current_state)
            IDLE, ENTRY_PROCESSING, EXIT_PROCESSING: begin
                if (vehicle_entry_sensor && !vehicle_exit_sensor) begin
                    if (available_spaces > ZERO_VAL) begin
                        next_available_spaces = available_spaces - ONE_VAL;
                        next_count_car        = count_car + ONE_VAL;
                        if (available_spaces == ONE_VAL) begin
                            next_state = FULL;
                        end else begin
                            next_state = ENTRY_PROCESSING;
                        end
                    end else begin
                        next_state = FULL;
                    end
                end else if (vehicle_exit_sensor && !vehicle_entry_sensor) begin
                    if (count_car > ZERO_VAL) begin
                        next_available_spaces = available_spaces + ONE_VAL;
                        next_count_car        = count_car - ONE_VAL;
                        next_state            = EXIT_PROCESSING;
                    end else begin
                        next_state = IDLE;
                    end
                end else if (vehicle_entry_sensor && vehicle_exit_sensor) begin
                    if (available_spaces == ZERO_VAL) begin
                        if (count_car > ZERO_VAL) begin
                            next_available_spaces = available_spaces + ONE_VAL;
                            next_count_car        = count_car - ONE_VAL;
                            next_state            = EXIT_PROCESSING;
                        end else begin
                            next_state = FULL;
                        end
                    end else if (count_car == ZERO_VAL) begin
                        next_available_spaces = available_spaces - ONE_VAL;
                        next_count_car        = count_car + ONE_VAL;
                        if (available_spaces == ONE_VAL) begin
                            next_state = FULL;
                        end else begin
                            next_state = ENTRY_PROCESSING;
                        end
                    end else begin
                        next_state = IDLE;
                    end
                end else begin
                    if (available_spaces == ZERO_VAL) begin
                        next_state = FULL;
                    end else begin
                        next_state = IDLE;
                    end
                end
            end

            FULL: begin
                if (vehicle_exit_sensor && (count_car > ZERO_VAL)) begin
                    next_available_spaces = available_spaces + ONE_VAL;
                    next_count_car        = count_car - ONE_VAL;
                    next_state            = EXIT_PROCESSING;
                end else begin
                    next_state = FULL;
                end
            end

            default: begin
                next_state            = IDLE;
                next_available_spaces = MAX_SPACES;
                next_count_car        = ZERO_VAL;
            end
        endcase
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state    <= (MAX_SPACES == ZERO_VAL) ? FULL : IDLE;
            available_spaces <= MAX_SPACES;
            count_car        <= ZERO_VAL;
        end else begin
            current_state    <= next_state;
            available_spaces <= next_available_spaces;
            count_car        <= next_count_car;
        end
    end

    assign led_status = (available_spaces > ZERO_VAL) ? 1'b1 : 1'b0;

    assign avail_ext = available_spaces;
    assign count_ext = count_car;
    assign avail_bcd = bin_to_bcd(avail_ext);
    assign count_bcd = bin_to_bcd(count_ext);

    assign seven_seg_display_available_tens  = encode_7seg(avail_bcd[7:4]);
    assign seven_seg_display_available_units = encode_7seg(avail_bcd[3:0]);
    assign seven_seg_display_count_tens      = encode_7seg(count_bcd[7:4]);
    assign seven_seg_display_count_units     = encode_7seg(count_bcd[3:0]);

endmodule
