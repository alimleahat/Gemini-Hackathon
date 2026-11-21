module matrix_multiplier #(
    parameter ROW_A             = 4,
    parameter COL_A             = 4,
    parameter ROW_B             = 4,
    parameter COL_B             = 4,
    parameter INPUT_DATA_WIDTH  = 8,
    parameter OUTPUT_DATA_WIDTH = (2 * INPUT_DATA_WIDTH) + $clog2(COL_A)
) (
    input  logic [(ROW_A * COL_A * INPUT_DATA_WIDTH) - 1 : 0]  matrix_a,
    input  logic [(ROW_B * COL_B * INPUT_DATA_WIDTH) - 1 : 0]  matrix_b,
    output logic [(ROW_A * COL_B * OUTPUT_DATA_WIDTH) - 1 : 0] matrix_c
);

    localparam PROD_WIDTH    = 2 * INPUT_DATA_WIDTH;
    localparam MIN_OUT_WIDTH = PROD_WIDTH + $clog2(COL_A);
    localparam ACC_WIDTH     = (OUTPUT_DATA_WIDTH > MIN_OUT_WIDTH) ? OUTPUT_DATA_WIDTH : MIN_OUT_WIDTH;

    wire [(ROW_A * COL_B * OUTPUT_DATA_WIDTH) - 1 : 0] matrix_c_int;

    genvar r, c, k;
    generate
        for (r = 0; r < ROW_A; r = r + 1) begin : gen_row
            for (c = 0; c < COL_B; c = c + 1) begin : gen_col
                wire [ACC_WIDTH - 1 : 0] partial_sum [0 : COL_A];
                wire [ACC_WIDTH - 1 : 0] final_sum;

                assign partial_sum[0] = {ACC_WIDTH{1'b0}};

                for (k = 0; k < COL_A; k = k + 1) begin : gen_mac
                    wire [INPUT_DATA_WIDTH - 1 : 0] a_elem;
                    wire [INPUT_DATA_WIDTH - 1 : 0] b_elem;
                    wire [PROD_WIDTH - 1 : 0]       prod;

                    assign a_elem = matrix_a[((r * COL_A + k) * INPUT_DATA_WIDTH) +: INPUT_DATA_WIDTH];
                    assign b_elem = matrix_b[((k * COL_B + c) * INPUT_DATA_WIDTH) +: INPUT_DATA_WIDTH];
                    assign prod   = a_elem * b_elem;

                    assign partial_sum[k + 1] = partial_sum[k] + prod;
                end

                assign final_sum = partial_sum[COL_A];
                assign matrix_c_int[((r * COL_B + c) * OUTPUT_DATA_WIDTH) +: OUTPUT_DATA_WIDTH] =
                    final_sum[OUTPUT_DATA_WIDTH - 1 : 0];
            end
        end
    endgenerate

    assign matrix_c = matrix_c_int;

endmodule

