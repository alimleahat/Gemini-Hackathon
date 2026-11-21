module matrix_multiplier #(
    parameter ROW_A             = 4,
    parameter COL_A             = 4,
    parameter ROW_B             = 4,
    parameter COL_B             = 4,
    parameter INPUT_DATA_WIDTH  = 8,
    parameter OUTPUT_DATA_WIDTH = (2 * INPUT_DATA_WIDTH) + ((COL_A > 1) ? $clog2(COL_A) : 0)
) (
    input  logic [(ROW_A * COL_A * INPUT_DATA_WIDTH) - 1 : 0]  matrix_a,
    input  logic [(ROW_B * COL_B * INPUT_DATA_WIDTH) - 1 : 0]  matrix_b,
    output logic [(ROW_A * COL_B * OUTPUT_DATA_WIDTH) - 1 : 0] matrix_c
);

    localparam MIN_OUT_WIDTH = (2 * INPUT_DATA_WIDTH) + ((COL_A > 1) ? $clog2(COL_A) : 0);
    localparam ACC_WIDTH     = (OUTPUT_DATA_WIDTH > MIN_OUT_WIDTH) ? OUTPUT_DATA_WIDTH : MIN_OUT_WIDTH;
    localparam PROD_WIDTH    = 2 * INPUT_DATA_WIDTH;

    genvar i, j;
    generate
        for (i = 0; i < ROW_A; i = i + 1) begin : gen_row
            for (j = 0; j < COL_B; j = j + 1) begin : gen_col
                logic [ACC_WIDTH-1:0]        sum;
                logic [INPUT_DATA_WIDTH-1:0] a_elem;
                logic [INPUT_DATA_WIDTH-1:0] b_elem;
                logic [PROD_WIDTH-1:0]       prod;
                integer k;

                always_comb begin
                    sum    = '0;
                    a_elem = '0;
                    b_elem = '0;
                    prod   = '0;
                    for (k = 0; k < COL_A; k = k + 1) begin
                        a_elem = matrix_a[((i * COL_A + k) * INPUT_DATA_WIDTH) +: INPUT_DATA_WIDTH];
                        b_elem = matrix_b[((k * COL_B + j) * INPUT_DATA_WIDTH) +: INPUT_DATA_WIDTH];
                        prod   = a_elem * b_elem;
                        sum    = sum + prod;
                    end
                end

                assign matrix_c[((i * COL_B + j) * OUTPUT_DATA_WIDTH) +: OUTPUT_DATA_WIDTH] = sum[OUTPUT_DATA_WIDTH-1:0];
            end
        end
    endgenerate

endmodule
