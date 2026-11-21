module qam16_mapper_interpolated #(
    parameter int N         = 4,
    parameter int IN_WIDTH  = 4,
    parameter int OUT_WIDTH = 3
) (
    input  wire [N*IN_WIDTH-1:0]          bits,
    output wire [(N + N/2)*OUT_WIDTH-1:0] I,
    output wire [(N + N/2)*OUT_WIDTH-1:0] Q
);

    genvar idx;
    generate
        for (idx = 0; idx < N/2; idx = idx + 1) begin : gen_qam16_pairs
            wire [IN_WIDTH-1:0] sym0;
            wire [IN_WIDTH-1:0] sym1;

            wire signed [OUT_WIDTH-1:0] i0;
            wire signed [OUT_WIDTH-1:0] q0;
            wire signed [OUT_WIDTH-1:0] i1;
            wire signed [OUT_WIDTH-1:0] q1;

            wire signed [OUT_WIDTH:0] sum_i;
            wire signed [OUT_WIDTH:0] sum_q;
            wire signed [OUT_WIDTH:0] interp_i;
            wire signed [OUT_WIDTH:0] interp_q;

            assign sym0 = bits[(2*idx)*IN_WIDTH +: IN_WIDTH];
            assign sym1 = bits[(2*idx + 1)*IN_WIDTH +: IN_WIDTH];

            assign i0 = (sym0[IN_WIDTH-1 : IN_WIDTH-2] == 2'b00) ? -3'sd3 :
                        (sym0[IN_WIDTH-1 : IN_WIDTH-2] == 2'b01) ? -3'sd1 :
                        (sym0[IN_WIDTH-1 : IN_WIDTH-2] == 2'b10) ?  3'sd1 :
                                                                    3'sd3;

            assign q0 = (sym0[1:0] == 2'b00) ? -3'sd3 :
                        (sym0[1:0] == 2'b01) ? -3'sd1 :
                        (sym0[1:0] == 2'b10) ?  3'sd1 :
                                                3'sd3;

            assign i1 = (sym1[IN_WIDTH-1 : IN_WIDTH-2] == 2'b00) ? -3'sd3 :
                        (sym1[IN_WIDTH-1 : IN_WIDTH-2] == 2'b01) ? -3'sd1 :
                        (sym1[IN_WIDTH-1 : IN_WIDTH-2] == 2'b10) ?  3'sd1 :
                                                                    3'sd3;

            assign q1 = (sym1[1:0] == 2'b00) ? -3'sd3 :
                        (sym1[1:0] == 2'b01) ? -3'sd1 :
                        (sym1[1:0] == 2'b10) ?  3'sd1 :
                                                3'sd3;

            assign sum_i    = i0 + i1;
            assign sum_q    = q0 + q1;
            assign interp_i = sum_i >>> 1;
            assign interp_q = sum_q >>> 1;

            assign I[(3*idx)*OUT_WIDTH +: OUT_WIDTH]     = i0;
            assign I[(3*idx + 1)*OUT_WIDTH +: OUT_WIDTH] = interp_i[OUT_WIDTH-1:0];
            assign I[(3*idx + 2)*OUT_WIDTH +: OUT_WIDTH] = i1;

            assign Q[(3*idx)*OUT_WIDTH +: OUT_WIDTH]     = q0;
            assign Q[(3*idx + 1)*OUT_WIDTH +: OUT_WIDTH] = interp_q[OUT_WIDTH-1:0];
            assign Q[(3*idx + 2)*OUT_WIDTH +: OUT_WIDTH] = q1;
        end
    endgenerate

endmodule
