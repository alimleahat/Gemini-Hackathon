module qam16_mapper_interpolated #(
    parameter int N         = 4,
    parameter int IN_WIDTH  = 4,
    parameter int OUT_WIDTH = 3
) (
    input  logic [N*IN_WIDTH-1:0]          bits,
    output logic [(N + N/2)*OUT_WIDTH-1:0] I,
    output logic [(N + N/2)*OUT_WIDTH-1:0] Q
);

    genvar p;
    generate
        for (p = 0; p < N / 2; p = p + 1) begin : gen_pair
            logic [1:0] i0_bits;
            logic [1:0] q0_bits;
            logic [1:0] i1_bits;
            logic [1:0] q1_bits;

            logic signed [OUT_WIDTH-1:0] i0;
            logic signed [OUT_WIDTH-1:0] q0;
            logic signed [OUT_WIDTH-1:0] i1;
            logic signed [OUT_WIDTH-1:0] q1;

            logic signed [OUT_WIDTH:0]   sum_i;
            logic signed [OUT_WIDTH:0]   sum_q;

            logic signed [OUT_WIDTH-1:0] interp_i;
            logic signed [OUT_WIDTH-1:0] interp_q;

            // Extract MSB (I) and LSB (Q) 2-bit pairs for two consecutive symbols
            assign i0_bits = bits[(2*p)*IN_WIDTH + IN_WIDTH - 2 +: 2];
            assign q0_bits = bits[(2*p)*IN_WIDTH +: 2];
            assign i1_bits = bits[(2*p + 1)*IN_WIDTH + IN_WIDTH - 2 +: 2];
            assign q1_bits = bits[(2*p + 1)*IN_WIDTH +: 2];

            // QAM16 mapping: 00 -> -3, 01 -> -1, 10 -> +1, 11 -> +3
            assign i0 = (i0_bits == 2'b00) ? 3'sb101 :
                        (i0_bits == 2'b01) ? 3'sb111 :
                        (i0_bits == 2'b10) ? 3'sb001 :
                                             3'sb011 ;

            assign q0 = (q0_bits == 2'b00) ? 3'sb101 :
                        (q0_bits == 2'b01) ? 3'sb111 :
                        (q0_bits == 2'b10) ? 3'sb001 :
                                             3'sb011 ;

            assign i1 = (i1_bits == 2'b00) ? 3'sb101 :
                        (i1_bits == 2'b01) ? 3'sb111 :
                        (i1_bits == 2'b10) ? 3'sb001 :
                                             3'sb011 ;

            assign q1 = (q1_bits == 2'b00) ? 3'sb101 :
                        (q1_bits == 2'b01) ? 3'sb111 :
                        (q1_bits == 2'b10) ? 3'sb001 :
                                             3'sb011 ;

            // Arithmetic mean interpolation using (OUT_WIDTH + 1)-bit signed sum
            assign sum_i    = $signed({i0[OUT_WIDTH-1], i0}) + $signed({i1[OUT_WIDTH-1], i1});
            assign sum_q    = $signed({q0[OUT_WIDTH-1], q0}) + $signed({q1[OUT_WIDTH-1], q1});
            assign interp_i = sum_i[OUT_WIDTH:1];
            assign interp_q = sum_q[OUT_WIDTH:1];

            // Pack outputs: first mapped symbol, interpolated value, second mapped symbol
            assign I[(3*p)*OUT_WIDTH     +: OUT_WIDTH] = i0;
            assign I[(3*p + 1)*OUT_WIDTH +: OUT_WIDTH] = interp_i;
            assign I[(3*p + 2)*OUT_WIDTH +: OUT_WIDTH] = i1;

            assign Q[(3*p)*OUT_WIDTH     +: OUT_WIDTH] = q0;
            assign Q[(3*p + 1)*OUT_WIDTH +: OUT_WIDTH] = interp_q;
            assign Q[(3*p + 2)*OUT_WIDTH +: OUT_WIDTH] = q1;
        end
    endgenerate

endmodule
