module qam16_mapper_interpolated #(
    parameter N         = 4,
    parameter IN_WIDTH  = 4,
    parameter OUT_WIDTH = 3
) (
    input  logic [N*IN_WIDTH-1:0]          bits,
    output logic [(N + N/2)*OUT_WIDTH-1:0] I,
    output logic [(N + N/2)*OUT_WIDTH-1:0] Q
);

    function automatic logic [OUT_WIDTH-1:0] map_comp(input logic [1:0] sel);
        case (sel)
            2'b00:   map_comp = 3'b101;
            2'b01:   map_comp = 3'b111;
            2'b10:   map_comp = 3'b001;
            2'b11:   map_comp = 3'b011;
            default: map_comp = 3'b000;
        endcase
    endfunction

    genvar p;
    generate
        for (p = 0; p < N / 2; p = p + 1) begin : gen_pair
            logic [IN_WIDTH-1:0]       sym0;
            logic [IN_WIDTH-1:0]       sym1;
            logic [OUT_WIDTH-1:0]      i0;
            logic [OUT_WIDTH-1:0]      i1;
            logic [OUT_WIDTH-1:0]      q0;
            logic [OUT_WIDTH-1:0]      q1;
            logic signed [OUT_WIDTH:0] sum_i;
            logic signed [OUT_WIDTH:0] sum_q;

            assign sym0 = bits[(2*p)*IN_WIDTH +: IN_WIDTH];
            assign sym1 = bits[(2*p + 1)*IN_WIDTH +: IN_WIDTH];

            assign i0 = map_comp(sym0[IN_WIDTH-1 : IN_WIDTH-2]);
            assign q0 = map_comp(sym0[1:0]);
            assign i1 = map_comp(sym1[IN_WIDTH-1 : IN_WIDTH-2]);
            assign q1 = map_comp(sym1[1:0]);

            assign sum_i = $signed({i0[OUT_WIDTH-1], i0}) + $signed({i1[OUT_WIDTH-1], i1});
            assign sum_q = $signed({q0[OUT_WIDTH-1], q0}) + $signed({q1[OUT_WIDTH-1], q1});

            assign I[(3*p)*OUT_WIDTH +: OUT_WIDTH]     = i0;
            assign I[(3*p + 1)*OUT_WIDTH +: OUT_WIDTH] = sum_i[OUT_WIDTH:1];
            assign I[(3*p + 2)*OUT_WIDTH +: OUT_WIDTH] = i1;

            assign Q[(3*p)*OUT_WIDTH +: OUT_WIDTH]     = q0;
            assign Q[(3*p + 1)*OUT_WIDTH +: OUT_WIDTH] = sum_q[OUT_WIDTH:1];
            assign Q[(3*p + 2)*OUT_WIDTH +: OUT_WIDTH] = q1;
        end
    endgenerate

endmodule
