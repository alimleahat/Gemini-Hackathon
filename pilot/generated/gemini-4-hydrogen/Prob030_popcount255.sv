module TopModule (
    input  [254:0] in,
    output reg [7:0] out
);
    integer i;

    always @(*) begin
        out = 8'd0;
        for (i = 0; i < 255; i = i + 1) begin
            out = out + {7'd0, in[i]};
        end
    end
endmodule
