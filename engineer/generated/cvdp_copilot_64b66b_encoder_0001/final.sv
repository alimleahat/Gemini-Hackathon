module encoder_64b66b (
    input  logic        clk_in,
    input  logic        rst_in,
    input  logic [63:0] encoder_data_in,
    input  logic [7:0]  encoder_control_in,
    output logic [65:0] encoder_data_out
);

    localparam logic [1:0] SYNC_DATA = 2'b01;
    localparam logic [1:0] SYNC_CTRL = 2'b10;

    always_ff @(posedge clk_in or posedge rst_in) begin
        if (rst_in) begin
            encoder_data_out <= 66'd0;
        end else if (encoder_control_in == 8'b0000_0000) begin
            encoder_data_out <= {SYNC_DATA, encoder_data_in};
        end else begin
            encoder_data_out <= {SYNC_CTRL, 64'd0};
        end
    end

endmodule
