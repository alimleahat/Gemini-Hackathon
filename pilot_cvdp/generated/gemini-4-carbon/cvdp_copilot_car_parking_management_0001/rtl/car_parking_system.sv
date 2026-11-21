module car_parking_system #(
    parameter TOTAL_SPACES = 12
) (
    input  wire                             clk,
    input  wire                             reset,
    input  wire                             vehicle_entry_sensor,
    input  wire                             vehicle_exit_sensor,
    output reg  [$clog2(TOTAL_SPACES)-1:0]  available_spaces,
    output reg  [$clog2(TOTAL_SPACES)-1:0]  count_car,
    output wire                             led_status,
    output wire [6:0]                       seven_seg_display_available_tens,
    output wire [6:0]                       seven_seg_display_available_units,
    output wire [6:0]                       seven_seg_display_count_tens,
    output wire [6:0]                       seven_seg_display_count_units
);

    localparam WIDTH = $clog2(TOTAL_SPACES);
    localparam [WIDTH-1:0] INIT_SPACES = TOTAL_SPACES;

    // FSM State Encoding
    localparam [1:0] IDLE             = 2'b00,
                     ENTRY_PROCESSING = 2'b01,
                     EXIT_PROCESSING  = 2'b10,
                     FULL             = 2'b11;

    reg [1:0] current_state, next_state;

    // Next-State Combinational Logic
    always @(*) begin
        next_state = IDLE;
        case (current_state)
            IDLE: begin
                if (vehicle_entry_sensor && !vehicle_exit_sensor) begin
                    if (available_spaces > 0)
                        next_state = ENTRY_PROCESSING;
                    else
                        next_state = FULL;
                end else if (vehicle_exit_sensor && !vehicle_entry_sensor && (count_car > 0)) begin
                    next_state = EXIT_PROCESSING;
                end else if (available_spaces == 0) begin
                    next_state = FULL;
                end else begin
                    next_state = IDLE;
                end
            end

            ENTRY_PROCESSING: begin
                if (available_spaces == 0) begin
                    if (vehicle_exit_sensor && !vehicle_entry_sensor && (count_car > 0))
                        next_state = EXIT_PROCESSING;
                    else
                        next_state = FULL;
                end else if (vehicle_entry_sensor && !vehicle_exit_sensor) begin
                    next_state = ENTRY_PROCESSING;
                end else if (vehicle_exit_sensor && !vehicle_entry_sensor && (count_car > 0)) begin
                    next_state = EXIT_PROCESSING;
                end else begin
                    next_state = IDLE;
                end
            end

            EXIT_PROCESSING: begin
                if (vehicle_entry_sensor && !vehicle_exit_sensor) begin
                    if (available_spaces > 0)
                        next_state = ENTRY_PROCESSING;
                    else
                        next_state = FULL;
                end else if (vehicle_exit_sensor && !vehicle_entry_sensor && (count_car > 0)) begin
                    next_state = EXIT_PROCESSING;
                end else if (available_spaces == 0) begin
                    next_state = FULL;
                end else begin
                    next_state = IDLE;
                end
            end

            FULL: begin
                if (vehicle_exit_sensor && !vehicle_entry_sensor && (count_car > 0))
                    next_state = EXIT_PROCESSING;
                else if (available_spaces > 0)
                    next_state = IDLE;
                else
                    next_state = FULL;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // State Register and Space/Car Counters
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state    <= IDLE;
            available_spaces <= INIT_SPACES;
            count_car        <= {WIDTH{1'b0}};
        end else begin
            current_state <= next_state;
            case (next_state)
                ENTRY_PROCESSING: begin
                    if (available_spaces > 0) begin
                        available_spaces <= available_spaces - 1'b1;
                        count_car        <= count_car + 1'b1;
                    end
                end
                EXIT_PROCESSING: begin
                    if (count_car > 0) begin
                        available_spaces <= available_spaces + 1'b1;
                        count_car        <= count_car - 1'b1;
                    end
                end
                default: begin
                    available_spaces <= available_spaces;
                    count_car        <= count_car;
                end
            endcase
        end
    end

    // LED Indicator: 1 = space available, 0 = parking full
    assign led_status = (available_spaces != 0);

    // 7-Segment Decoder (MSB = Segment A, LSB = Segment G)
    function automatic [6:0] bcd_to_7seg;
        input [3:0] bcd;
        begin
            case (bcd)
                4'd0:    bcd_to_7seg = 7'b1111110;
                4'd1:    bcd_to_7seg = 7'b0110000;
                4'd2:    bcd_to_7seg = 7'b1101101;
                4'd3:    bcd_to_7seg = 7'b1111001;
                4'd4:    bcd_to_7seg = 7'b0110011;
                4'd5:    bcd_to_7seg = 7'b1011011;
                4'd6:    bcd_to_7seg = 7'b1011111;
                4'd7:    bcd_to_7seg = 7'b1110000;
                4'd8:    bcd_to_7seg = 7'b1111111;
                4'd9:    bcd_to_7seg = 7'b1111011;
                default: bcd_to_7seg = 7'b0000000;
            endcase
        end
    endfunction

    wire [7:0] avail_ext = 8'd0 + available_spaces;
    wire [7:0] count_ext = 8'd0 + count_car;

    wire [7:0] avail_tens  = (avail_ext / 8'd10) % 8'd10;
    wire [7:0] avail_units = avail_ext % 8'd10;
    wire [7:0] count_tens  = (count_ext / 8'd10) % 8'd10;
    wire [7:0] count_units = count_ext % 8'd10;

    assign seven_seg_display_available_tens  = bcd_to_7seg(avail_tens[3:0]);
    assign seven_seg_display_available_units = bcd_to_7seg(avail_units[3:0]);
    assign seven_seg_display_count_tens      = bcd_to_7seg(count_tens[3:0]);
    assign seven_seg_display_count_units     = bcd_to_7seg(count_units[3:0]);

endmodule
