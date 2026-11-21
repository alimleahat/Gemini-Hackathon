module TopModule (
    input  wire        clk,
    input  wire        reset,
    output reg  [31:0] q
);

    always @(posedge clk) begin
        if (reset) begin
            q <= 32'h1;
        end else begin
            q <= {1'b0, q[31:1]} ^ (q[0] ? 32'h8020_0003 : 32'h0);
        end
    end

endmodule
