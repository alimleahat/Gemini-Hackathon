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
    logic signed [31:0] real_next;
    logic signed [31:0] imag_next;

    assign prod_ac   = a_real * b_real;
    assign prod_bd   = a_imag * b_imag;
    assign prod_ad   = a_real * b_imag;
    assign prod_bc   = a_imag * b_real;

    assign real_next = prod_ac - prod_bd;
    assign imag_next = prod_ad + prod_bc;

    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            result_real <= 32'sd0;
            result_imag <= 32'sd0;
        end else begin
            result_real <= real_next;
            result_imag <= imag_next;
        end
    end

endmodule
