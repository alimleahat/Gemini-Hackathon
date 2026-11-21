module qam16_mapper_interpolated #(
    parameter N         = 4,
    parameter IN_WIDTH  = 4,
    parameter OUT_WIDTH = 3
) (
    input  logic [N*IN_WIDTH-1:0]          bits,
    output logic [(N + N/2)*OUT_WIDTH-1:0] I,
    output logic [(N + N/2)*OUT_WIDTH-1:0] Q
);

    localparam HALF_N      = N / 2;
    localparam TOTAL_PAIRS = 2 * HALF_N;

    logic [4*TOTAL_PAIRS-1:0] add1_a, add1_b, add1_s;
    logic [3*TOTAL_PAIRS-1:0] add2_a, add2_b, add2_s;

    assign add1_s = add1_a + add1_b;
    assign add2_s = add2_a + add2_b;

    genvar p;
    generate
        for (p = 0; p < HALF_N; p = p + 1) begin : gen_pair
            logic [1:0] i_a, i_b, q_a, q_b;

            assign i_a = bits[(2*p)*IN_WIDTH + IN_WIDTH - 2 +: 2];
            assign i_b = bits[(2*p + 1)*IN_WIDTH + IN_WIDTH - 2 +: 2];
            assign q_a = bits[(2*p)*IN_WIDTH +: 2];
            assign q_b = bits[(2*p + 1)*IN_WIDTH +: 2];

            // Real (I) pair interpolation
            assign add1_a[4*p +: 4] = {1'b1, i_a[1], 1'b1, i_a[0]};
            assign add1_b[4*p +: 4] = {1'b0, 1'b0, i_b[0], i_a[0]};
            assign add2_a[3*p +: 3] = {add1_s[4*p + 3], add1_s[4*p + 2], i_b[1]};
            assign add2_b[3*p +: 3] = {1'b0, 1'b0, i_b[1]};

            assign I[(3*p)*OUT_WIDTH +: OUT_WIDTH]     = {~i_a[1], i_a[0], 1'b1};
            assign I[(3*p + 1)*OUT_WIDTH +: OUT_WIDTH] = {add2_s[3*p + 2], add2_s[3*p + 1], add1_s[4*p + 1]};
            assign I[(3*p + 2)*OUT_WIDTH +: OUT_WIDTH] = {~i_b[1], i_b[0], 1'b1};

            // Imaginary (Q) pair interpolation
            assign add1_a[4*(HALF_N + p) +: 4] = {1'b1, q_a[1], 1'b1, q_a[0]};
            assign add1_b[4*(HALF_N + p) +: 4] = {1'b0, 1'b0, q_b[0], q_a[0]};
            assign add2_a[3*(HALF_N + p) +: 3] = {add1_s[4*(HALF_N + p) + 3], add1_s[4*(HALF_N + p) + 2], q_b[1]};
            assign add2_b[3*(HALF_N + p) +: 3] = {1'b0, 1'b0, q_b[1]};

            assign Q[(3*p)*OUT_WIDTH +: OUT_WIDTH]     = {~q_a[1], q_a[0], 1'b1};
            assign Q[(3*p + 1)*OUT_WIDTH +: OUT_WIDTH] = {add2_s[3*(HALF_N + p) + 2], add2_s[3*(HALF_N + p) + 1], add1_s[4*(HALF_N + p) + 1]};
            assign Q[(3*p + 2)*OUT_WIDTH +: OUT_WIDTH] = {~q_b[1], q_b[0], 1'b1};
        end
    endgenerate

endmodule
