module moving_average (
    input  wire        clk,
    input  wire        reset,
    input  wire [11:0] data_in,
    output reg  [11:0] data_out
);

    reg  [11:0] buffer [0:7];
    reg  [15:0] sum;
    wire [15:0] next_sum;
    integer     i;

    assign next_sum = sum + {4'd0, data_in} - {4'd0, buffer[7]};

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 8; i = i + 1) begin
                buffer[i] <= 12'd0;
            end
            sum      <= 16'd0;
            data_out <= 12'd0;
        end else begin
            buffer[0] <= data_in;
            for (i = 1; i < 8; i = i + 1) begin
                buffer[i] <= buffer[i - 1];
            end
            sum      <= next_sum;
            data_out <= next_sum[14:3];
        end
    end

endmodule
