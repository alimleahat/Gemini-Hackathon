module moving_average (
    input  wire        clk,
    input  wire        reset,
    input  wire [11:0] data_in,
    output wire [11:0] data_out
);

    reg [11:0] buffer [0:7];
    reg [14:0] sum;
    reg [2:0]  cnt;
    reg        full;
    integer    i;

    wire [11:0] oldest = full ? buffer[7] : 12'd0;

    always @(posedge clk) begin
        buffer[0] <= data_in;
        for (i = 1; i < 8; i = i + 1) begin
            buffer[i] <= buffer[i - 1];
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            sum  <= 15'd0;
            cnt  <= 3'b000;
            full <= 1'b0;
        end else begin
            sum <= (sum - {3'd0, oldest}) + {3'd0, data_in};
            cnt <= {cnt[1:0], cnt[2] ^ (cnt[1] | ~cnt[0])};
            if (cnt == 3'b100) begin
                full <= 1'b1;
            end
        end
    end

    assign data_out = sum[14:3];

endmodule
