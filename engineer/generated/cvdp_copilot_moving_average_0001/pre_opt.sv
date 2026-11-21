module moving_average (
    input  wire        clk,
    input  wire        reset,
    input  wire [11:0] data_in,
    output wire [11:0] data_out
);

    reg [11:0] buffer [0:7];
    reg [14:0] sum;
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 8; i = i + 1) begin
                buffer[i] <= 12'd0;
            end
            sum <= 15'd0;
        end else begin
            buffer[0] <= data_in;
            for (i = 1; i < 8; i = i + 1) begin
                buffer[i] <= buffer[i - 1];
            end
            sum <= (sum - {3'd0, buffer[7]}) + {3'd0, data_in};
        end
    end

    assign data_out = sum[14:3];

endmodule
