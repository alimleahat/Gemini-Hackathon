module matrix_multiplier #(
    parameter ROW_A = 4,
    parameter COL_A = 4,
    parameter ROW_B = 4,
    parameter COL_B = 4,
    parameter INPUT_DATA_WIDTH = 8,
    parameter OUTPUT_DATA_WIDTH = (2 * INPUT_DATA_WIDTH) + $clog2(COL_A)
) (
    input  wire [(ROW_A * COL_A * INPUT_DATA_WIDTH) - 1 : 0]  matrix_a,
    input  wire [(ROW_B * COL_B * INPUT_DATA_WIDTH) - 1 : 0]  matrix_b,
    output wire [(ROW_A * COL_B * OUTPUT_DATA_WIDTH) - 1 : 0] matrix_c
);

    localparam CALC_WIDTH = (2 * INPUT_DATA_WIDTH) + $clog2(COL_A);
    localparam ACC_WIDTH  = (OUTPUT_DATA_WIDTH > CALC_WIDTH) ? OUTPUT_DATA_WIDTH : CALC_WIDTH;

    genvar i, j, k;
    generate
        for (i = 0; i < ROW_A; i = i + 1) begin : gen_row
            for (j = 0; j < COL_B; j = j + 1) begin : gen_col
                wire [((COL_A + 1) * ACC_WIDTH) - 1 : 0] partial_sum;
                assign partial_sum[0 +: ACC_WIDTH] = {ACC_WIDTH{1'b0}};

                for (k = 0; k < COL_A; k = k + 1) begin : gen_k
                    wire [INPUT_DATA_WIDTH - 1 : 0]       a_elem;
                    wire [INPUT_DATA_WIDTH - 1 : 0]       b_elem;
                    wire [(2 * INPUT_DATA_WIDTH) - 1 : 0] prod;

                    assign a_elem = matrix_a[((i * COL_A) + k) * INPUT_DATA_WIDTH +: INPUT_DATA_WIDTH];
                    assign b_elem = matrix_b[((k * COL_B) + j) * INPUT_DATA_WIDTH +: INPUT_DATA_WIDTH];
                    assign prod   = a_elem * b_elem;
                    assign partial_sum[(k + 1) * ACC_WIDTH +: ACC_WIDTH] =
                        partial_sum[k * ACC_WIDTH +: ACC_WIDTH] + prod;
                end

                assign matrix_c[((i * COL_B) + j) * OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] =
                    partial_sum[COL_A * ACC_WIDTH +: OUTPUT_DATA_WIDTH];
            end
        end
    endgenerate

endmodule
