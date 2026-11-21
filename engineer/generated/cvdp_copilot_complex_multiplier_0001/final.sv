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

    logic signed [15:0] a_real_q;
    logic signed [15:0] a_imag_q;
    logic signed [15:0] b_real_q = 16'sd0;
    logic signed [15:0] b_imag_q = 16'sd0;

    logic signed [16:0] diff_b;
    logic signed [16:0] diff_a;
    logic signed [16:0] sum_a;

    logic signed [31:0] p1;
    logic signed [31:0] p2;
    logic signed [31:0] p3;

    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            a_real_q <= 16'sd0;
            a_imag_q <= 16'sd0;
        end else begin
            a_real_q <= a_real;
            a_imag_q <= a_imag;
        end
    end

    always @(posedge clk) begin
        if (!arst_n) begin
            b_real_q <= 16'sd0;
            b_imag_q <= 16'sd0;
        end else begin
            b_real_q <= b_real;
            b_imag_q <= b_imag;
        end
    end

    assign diff_b      = b_real_q - b_imag_q;
    assign diff_a      = a_real_q - a_imag_q;
    assign sum_a       = a_real_q + a_imag_q;

    assign p1          = diff_b * a_imag_q;
    assign p2          = diff_a * b_real_q;
    assign p3          = sum_a  * b_imag_q;

    assign result_real = p2 + p1;
    assign result_imag = p3 + p1;

endmodule
