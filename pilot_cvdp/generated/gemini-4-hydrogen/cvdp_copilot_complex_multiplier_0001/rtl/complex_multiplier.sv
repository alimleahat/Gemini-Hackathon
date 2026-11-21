module complex_multiplier (
    input  logic               clk,
    input  logic               arst_n,
    input  logic signed [15:0] a_real,
    input  logic signed [15:0] a_imag,
    input  logic signed [15:0] b_real,
    input  logic signed [15:0] b_imag,
    output logic signed [31:0] result_real,
    output logic signed [31:0] result_imag
);

    logic signed [31:0] prod_ac;
    logic signed [31:0] prod_bd;
    logic signed [31:0] prod_ad;
    logic signed [31:0] prod_bc;

    always_comb begin
        prod_ac = a_real * b_real;
        prod_bd = a_imag * b_imag;
        prod_ad = a_real * b_imag;
        prod_bc = a_imag * b_real;
    end

    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            result_real <= 32'sd0;
            result_imag <= 32'sd0;
        end else begin
            result_real <= prod_ac - prod_bd;
            result_imag <= prod_ad + prod_bc;
        end
    end

endmodule
