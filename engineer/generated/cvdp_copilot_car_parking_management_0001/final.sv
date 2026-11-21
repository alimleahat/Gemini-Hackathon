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
    localparam logic [COUNT_WIDTH-1:0] MAX_SPACES = TOTAL_SPACES[COUNT_WIDTH-1:0];

    logic                   can_inc;
    logic                   can_dec;
    logic                   inc_only;
    logic                   dec_only;
    logic [COUNT_WIDTH-1:0] carry_inc;
    logic [COUNT_WIDTH-1:0] carry_dec;
    logic [COUNT_WIDTH-1:0] next_count;
    logic [COUNT_WIDTH:0]   borrow;
    logic [7:0]             available_bcd;
    logic [7:0]             count_bcd;

    assign led_status = (count_car != MAX_SPACES);

    assign can_inc  = vehicle_entry_sensor & led_status;
    assign can_dec  = vehicle_exit_sensor  & (|count_car);
    assign inc_only = can_inc & ~can_dec;
    assign dec_only = can_dec & ~can_inc;

    assign carry_inc[0] = inc_only;
    assign carry_dec[0] = dec_only;

    genvar i;
    generate
        for (i = 1; i < COUNT_WIDTH; i = i + 1) begin : gen_cnt_carry
            assign carry_inc[i] = carry_inc[i-1] &  count_car[i-1];
            assign carry_dec[i] = carry_dec[i-1] & ~count_car[i-1];
        end
    endgenerate

    assign next_count = count_car ^ (carry_inc | carry_dec);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            count_car <= {COUNT_WIDTH{1'b0}};
        end else begin
            count_car <= next_count;
        end
    end

    assign borrow[0] = 1'b0;
    generate
        for (i = 0; i < COUNT_WIDTH; i = i + 1) begin : gen_avail_sub
            assign available_spaces[i] = MAX_SPACES[i] ^ count_car[i] ^ borrow[i];
            assign borrow[i+1]         = (~MAX_SPACES[i] & count_car[i]) |
                                         ((~MAX_SPACES[i] | count_car[i]) & borrow[i]);
        end
    endgenerate

    function automatic logic [7:0] bin_to_bcd(input logic [COUNT_WIDTH-1:0] val);
        logic [11:0] bcd;
        logic [3:0]  tens;
        integer      k;
        bcd = 12'd0;
        for (k = COUNT_WIDTH - 1; k >= 0; k = k - 1) begin
            case (bcd[3:0])
                4'd5:    bcd[3:0] = 4'd8;
                4'd6:    bcd[3:0] = 4'd9;
                4'd7:    bcd[3:0] = 4'd10;
                4'd8:    bcd[3:0] = 4'd11;
                4'd9:    bcd[3:0] = 4'd12;
                default: bcd[3:0] = bcd[3:0];
            endcase
            case (bcd[7:4])
                4'd5:    bcd[7:4] = 4'd8;
                4'd6:    bcd[7:4] = 4'd9;
                4'd7:    bcd[7:4] = 4'd10;
                4'd8:    bcd[7:4] = 4'd11;
                4'd9:    bcd[7:4] = 4'd12;
                default: bcd[7:4] = bcd[7:4];
            endcase
            case (bcd[11:8])
                4'd5:    bcd[11:8] = 4'd8;
                4'd6:    bcd[11:8] = 4'd9;
                4'd7:    bcd[11:8] = 4'd10;
                4'd8:    bcd[11:8] = 4'd11;
                4'd9:    bcd[11:8] = 4'd12;
                default: bcd[11:8] = bcd[11:8];
            endcase
            bcd = {bcd[10:0], val[k]};
        end
        tens = (|bcd[11:8]) ? 4'd10 : bcd[7:4];
        bin_to_bcd = {tens, bcd[3:0]};
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

    assign available_bcd = bin_to_bcd(available_spaces);
    assign count_bcd     = bin_to_bcd(count_car);

    assign seven_seg_display_available_tens  = encode_7seg(available_bcd[7:4]);
    assign seven_seg_display_available_units = encode_7seg(available_bcd[3:0]);
    assign seven_seg_display_count_tens      = encode_7seg(count_bcd[7:4]);
    assign seven_seg_display_count_units     = encode_7seg(count_bcd[3:0]);

endmodule
