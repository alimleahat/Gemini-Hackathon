module qam16_mapper_interpolated #(
    parameter N         = 4,
    parameter IN_WIDTH  = 4,
    parameter OUT_WIDTH = 3
) (
    input  logic [N*IN_WIDTH-1:0]        bits,
    output logic [(N + N/2)*OUT_WIDTH-1:0] I,
    output logic [(N + N/2)*OUT_WIDTH-1:0] Q
);

    logic signed [OUT_WIDTH-1:0] mapped_I [0:N-1];
    logic signed [OUT_WIDTH-1:0] mapped_Q [0:N-1];

    genvar i, p;
    generate
        for (i = 0; i < N; i = i + 1) begin : gen_map
            logic [1:0] bits_I;
            logic [1:0] bits_Q;
            logic signed [OUT_WIDTH-1:0] sym_I;
            logic signed [OUT_WIDTH-1:0] sym_Q;

            assign bits_I = bits[i*IN_WIDTH + IN_WIDTH - 2 +: 2];
            assign bits_Q = bits[i*IN_WIDTH +: 2];

            always_comb begin
                case (bits_I)
                    2'b00:   sym_I = 3'sb101; // -3
                    2'b01:   sym_I = 3'sb111; // -1
                    2'b10:   sym_I = 3'sb001; //  1
                    2'b11:   sym_I = 3'sb011; //  3
                    default: sym_I = 3'sb000;
                endcase

                case (bits_Q)
                    2'b00:   sym_Q = 3'sb101; // -3
                    2'b01:   sym_Q = 3'sb111; // -1
                    2'b10:   sym_Q = 3'sb001; //  1
                    2'b11:   sym_Q = 3'sb011; //  3
                    default: sym_Q = 3'sb000;
                endcase
            end

            assign mapped_I[i] = sym_I;
            assign mapped_Q[i] = sym_Q;
        end

        for (p = 0; p < N/2; p = p + 1) begin : gen_interp
            logic signed [OUT_WIDTH:0] sum_I;
            logic signed [OUT_WIDTH:0] sum_Q;
            logic signed [OUT_WIDTH:0] interp_I;
            logic signed [OUT_WIDTH:0] interp_Q;

            assign sum_I    = {mapped_I[2*p][OUT_WIDTH-1], mapped_I[2*p]} +
                              {mapped_I[2*p + 1][OUT_WIDTH-1], mapped_I[2*p + 1]};
            assign sum_Q    = {mapped_Q[2*p][OUT_WIDTH-1], mapped_Q[2*p]} +
                              {mapped_Q[2*p + 1][OUT_WIDTH-1], mapped_Q[2*p + 1]};

            assign interp_I = sum_I >>> 1;
            assign interp_Q = sum_Q >>> 1;

            assign I[(3*p)*OUT_WIDTH +: OUT_WIDTH]     = mapped_I[2*p];
            assign I[(3*p + 1)*OUT_WIDTH +: OUT_WIDTH] = interp_I[OUT_WIDTH-1:0];
            assign I[(3*p + 2)*OUT_WIDTH +: OUT_WIDTH] = mapped_I[2*p + 1];

            assign Q[(3*p)*OUT_WIDTH +: OUT_WIDTH]     = mapped_Q[2*p];
            assign Q[(3*p + 1)*OUT_WIDTH +: OUT_WIDTH] = interp_Q[OUT_WIDTH-1:0];
            assign Q[(3*p + 2)*OUT_WIDTH +: OUT_WIDTH] = mapped_Q[2*p + 1];
        end
    endgenerate

endmodule
