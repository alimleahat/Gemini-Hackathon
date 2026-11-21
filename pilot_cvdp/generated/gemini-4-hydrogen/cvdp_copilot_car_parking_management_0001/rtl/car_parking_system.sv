module car_parking_system #(
    parameter int TOTAL_SPACES = 12
) (
    input  logic                               clk,
    input  logic                               reset,
    input  logic                               vehicle_entry_sensor,
    input  logic                               vehicle_exit_sensor,
    output logic [$clog2(TOTAL_SPACES)-1:0]    available_spaces,
    output logic [$clog2(TOTAL_SPACES)-1:0]    count_car,
    output logic                               led_status,
    output logic [6:0]                         seven_seg_display_available_tens,
    output logic [6:0]                         seven_seg_display_available_units,
    output logic [6:0]                         seven_seg_display_count_tens,
    output logic [6:0]                         seven_seg_display_count_units
);

    localparam int WIDTH = $clog2(TOTAL_SPACES);
    localparam logic [WIDTH-1:0] INIT_SPACES = TOTAL_SPACES[WIDTH-1:0];

    localparam logic [1:0] IDLE  = 2'b00;
    localparam logic [1:0] ENTRY = 2'b01;
    localparam logic [1:0] EXIT  = 2'b10;
    localparam logic [1:0] FULL  = 2'b11;

    logic [1:0] state, next_state;

    logic [3:0] avail_tens, avail_units;
    logic [3:0] count_tens, count_units;

    function automatic logic [6:0] seg7_encode(input logic [3:0] digit);
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
    endfunction

    always_comb begin
        next_state = state;
        if (available_spaces == '0) begin
            if (vehicle_exit_sensor) begin
                next_state = EXIT;
            end else begin
                next_state = FULL;
            end
        end else begin
            if (vehicle_entry_sensor && !vehicle_exit_sensor) begin
                next_state = ENTRY;
            end else if (!vehicle_entry_sensor && vehicle_exit_sensor) begin
                if (count_car > '0) begin
                    next_state = EXIT;
                end else begin
                    next_state = IDLE;
                end
            end else if (vehicle_entry_sensor && vehicle_exit_sensor) begin
                if (count_car == '0) begin
                    next_state = ENTRY;
                end else begin
                    next_state = IDLE;
                end
            end else begin
                next_state = IDLE;
            end
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state            <= IDLE;
            available_spaces <= INIT_SPACES;
            count_car        <= '0;
        end else begin
            state <= next_state;
            case (next_state)
                ENTRY: begin
                    available_spaces <= available_spaces - {{(WIDTH-1){1'b0}}, 1'b1};
                    count_car        <= count_car + {{(WIDTH-1){1'b0}}, 1'b1};
                end
                EXIT: begin
                    available_spaces <= available_spaces + {{(WIDTH-1){1'b0}}, 1'b1};
                    count_car        <= count_car - {{(WIDTH-1){1'b0}}, 1'b1};
                end
                default: begin
                    available_spaces <= available_spaces;
                    count_car        <= count_car;
                end
            endcase
        end
    end

    assign led_status = (available_spaces > '0);

    assign avail_tens  = available_spaces / 32'd10;
    assign avail_units = available_spaces % 32'd10;
    assign count_tens  = count_car / 32'd10;
    assign count_units = count_car % 32'd10;

    assign seven_seg_display_available_tens  = seg7_encode(avail_tens);
    assign seven_seg_display_available_units = seg7_encode(avail_units);
    assign seven_seg_display_count_tens      = seg7_encode(count_tens);
    assign seven_seg_display_count_units     = seg7_encode(count_units);

endmodule
