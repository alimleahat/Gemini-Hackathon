module qam16_mapper_interpolated #(
    parameter int N         = 4,
    parameter int IN_WIDTH  = 4,
    parameter int OUT_WIDTH = 3
) (
    input  logic [N*IN_WIDTH-1:0]          bits,
    output logic [(N + N/2)*OUT_WIDTH-1:0] I,
    output logic [(N + N/2)*OUT_WIDTH-1:0] Q
);

    function automatic logic signed [OUT_WIDTH-1:0] map_2bit(input logic [1:0] b);
        case (b)
            2'b00:   map_2bit = 3'sb101; // -3
            2'b01:   map_2bit = 3'sb111; // -1
            2'b10:   map_2bit = 3'sb001; // +1
            2'b11:   map_2bit = 3'sb011; // +3
            default: map_2bit = 3'sb000;
        endcase
    endfunction

    genvar k;
    generate
        for (k = 0; k < N / 2; k = k + 1) begin : gen_pair
            logic [IN_WIDTH-1:0] sym0;
            logic [IN_WIDTH-1:0] sym1;

            logic signed [OUT_WIDTH-1:0] i0;
            logic signed [OUT_WIDTH-1:0] i1;
            logic signed [OUT_WIDTH-1:0] q0;
            logic signed [OUT_WIDTH-1:0] q1;

            logic signed [OUT_WIDTH:0] i_sum;
            logic signed [OUT_WIDTH:0] q_sum;
            logic signed [OUT_WIDTH:0] i_interp;
            logic signed [OUT_WIDTH:0] q_interp;

            assign sym0 = bits[(2 * k) * IN_WIDTH +: IN_WIDTH];
            assign sym1 = bits[(2 * k + 1) * IN_WIDTH +: IN_WIDTH];

            assign i0 = map_2bit(sym0[IN_WIDTH-1:IN_WIDTH-2]);
            assign q0 = map_2bit(sym0[1:0]);

            assign i1 = map_2bit(sym1[IN_WIDTH-1:IN_WIDTH-2]);
            assign q1 = map_2bit(sym1[1:0]);

            assign i_sum = $signed({i0[OUT_WIDTH-1], i0}) + $signed({i1[OUT_WIDTH-1], i1});
            assign q_sum = $signed({q0[OUT_WIDTH-1], q0}) + $signed({q1[OUT_WIDTH-1], q1});

            assign i_interp = i_sum >>> 1;
            assign q_interp = q_sum >>> 1;

            assign I[(3 * k) * OUT_WIDTH +: OUT_WIDTH]     = i0;
            assign I[(3 * k + 1) * OUT_WIDTH +: OUT_WIDTH] = i_interp[OUT_WIDTH-1:0];
            assign I[(3 * k + 2) * OUT_WIDTH +: OUT_WIDTH] = i1;

            assign Q[(3 * k) * OUT_WIDTH +: OUT_WIDTH]     = q0;
            assign Q[(3 * k + 1) * OUT_WIDTH +: OUT_WIDTH] = q_interp[OUT_WIDTH-1:0];
            assign Q[(3 * k + 2) * OUT_WIDTH +: OUT_WIDTH] = q1;
        end
    endgenerate

endmodule
