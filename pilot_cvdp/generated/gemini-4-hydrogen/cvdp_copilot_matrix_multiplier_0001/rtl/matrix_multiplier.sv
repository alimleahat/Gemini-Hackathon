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

    localparam ACC_WIDTH = (2 * INPUT_DATA_WIDTH) + $clog2(COL_A);

    genvar r, c;
    generate
        for (r = 0; r < ROW_A; r = r + 1) begin : gen_row
            for (c = 0; c < COL_B; c = c + 1) begin : gen_col
                logic [ACC_WIDTH - 1 : 0] acc;
                logic [(2 * INPUT_DATA_WIDTH) - 1 : 0] prod;
                integer k;

                always_comb begin
                    acc = {ACC_WIDTH{1'b0}};
                    for (k = 0; k < COL_A; k = k + 1) begin
                        prod = matrix_a[((r * COL_A + k) * INPUT_DATA_WIDTH) +: INPUT_DATA_WIDTH] *
                               matrix_b[((k * COL_B + c) * INPUT_DATA_WIDTH) +: INPUT_DATA_WIDTH];
                        acc = acc + prod;
                    end
                end

                assign matrix_c[((r * COL_B + c) * OUTPUT_DATA_WIDTH) +: OUTPUT_DATA_WIDTH] = acc;
            end
        end
    endgenerate

endmodule
