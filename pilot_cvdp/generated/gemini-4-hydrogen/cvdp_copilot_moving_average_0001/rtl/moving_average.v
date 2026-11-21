module moving_average (
    input  logic        clk,
    input  logic        reset,
    input  logic [11:0] data_in,
    output logic [11:0] data_out
);

    logic [11:0] buffer [0:7];
    logic [14:0] sum;
    logic [15:0] next_sum;

    assign next_sum = {1'b0, sum} + {4'b0, data_in} - {4'b0, buffer[7]};

    always_ff @(posedge clk) begin
        if (reset) begin
            buffer[0] <= 12'd0;
            buffer[1] <= 12'd0;
            buffer[2] <= 12'd0;
            buffer[3] <= 12'd0;
            buffer[4] <= 12'd0;
            buffer[5] <= 12'd0;
            buffer[6] <= 12'd0;
            buffer[7] <= 12'd0;
            sum       <= 15'd0;
        end else begin
            buffer[0] <= data_in;
            buffer[1] <= buffer[0];
            buffer[2] <= buffer[1];
            buffer[3] <= buffer[2];
            buffer[4] <= buffer[3];
            buffer[5] <= buffer[4];
            buffer[6] <= buffer[5];
            buffer[7] <= buffer[6];
            sum       <= next_sum[14:0];
        end
    end

    assign data_out = sum[14:3];

endmodule
