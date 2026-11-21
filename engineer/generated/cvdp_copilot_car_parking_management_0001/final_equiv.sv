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

    localparam COUNT_WIDTH = $clog2(TOTAL_SPACES);

    typedef enum logic [1:0] {
        IDLE             = 2'b00,
        ENTRY_PROCESSING = 2'b01,
        EXIT_PROCESSING  = 2'b10,
        FULL             = 2'b11
    } state_t;

    state_t                 current_state, next_state;
    logic [COUNT_WIDTH-1:0] next_available;
    logic [COUNT_WIDTH-1:0] next_count;

    logic [6:0] available_ext;
    logic [6:0] count_ext;
    logic [3:0] available_tens;
    logic [3:0] available_units;
    logic [3:0] count_tens;
    logic [3:0] count_units;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state    <= IDLE;
            available_spaces <= TOTAL_SPACES[COUNT_WIDTH-1:0];
            count_car        <= {COUNT_WIDTH{1'b0}};
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
            IDLE, ENTRY_PROCESSING, EXIT_PROCESSING: begin
                if (vehicle_entry_sensor && !vehicle_exit_sensor) begin
                    if (available_spaces > 0) begin
                        next_available = available_spaces - 1'b1;
                        next_count     = count_car + 1'b1;
                        if (available_spaces == 1)
                            next_state = FULL;
                        else
                            next_state = ENTRY_PROCESSING;
                    end else begin
                        next_state = FULL;
                    end
                end else if (vehicle_exit_sensor && !vehicle_entry_sensor) begin
                    if (count_car > 0) begin
                        next_available = available_spaces + 1'b1;
                        next_count     = count_car - 1'b1;
                        next_state     = EXIT_PROCESSING;
                    end else begin
                        next_state = IDLE;
                    end
                end else if (vehicle_entry_sensor && vehicle_exit_sensor) begin
                    if (available_spaces > 0 && count_car > 0) begin
                        next_state = IDLE;
                    end else if (available_spaces > 0) begin
                        next_available = available_spaces - 1'b1;
                        next_count     = count_car + 1'b1;
                        if (available_spaces == 1)
                            next_state = FULL;
                        else
                            next_state = ENTRY_PROCESSING;
                    end else if (count_car > 0) begin
                        next_available = available_spaces + 1'b1;
                        next_count     = count_car - 1'b1;
                        next_state     = EXIT_PROCESSING;
                    end else begin
                        next_state = IDLE;
                    end
                end else begin
                    if (available_spaces == 0)
                        next_state = FULL;
                    else
                        next_state = IDLE;
                end
            end

            FULL: begin
                if (vehicle_exit_sensor) begin
                    if (count_car > 0) begin
                        next_available = available_spaces + 1'b1;
                        next_count     = count_car - 1'b1;
                        next_state     = EXIT_PROCESSING;
                    end else begin
                        next_state = IDLE;
                    end
                end else begin
                    next_state = FULL;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    assign led_status = (available_spaces > 0);

    assign available_ext   = available_spaces;
    assign count_ext       = count_car;
    assign available_tens  = available_ext / 7'd10;
    assign available_units = available_ext % 7'd10;
    assign count_tens      = count_ext / 7'd10;
    assign count_units     = count_ext % 7'd10;

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

    assign seven_seg_display_available_tens  = encode_7seg(available_tens);
    assign seven_seg_display_available_units = encode_7seg(available_units);
    assign seven_seg_display_count_tens      = encode_7seg(count_tens);
    assign seven_seg_display_count_units     = encode_7seg(count_units);

endmodule

