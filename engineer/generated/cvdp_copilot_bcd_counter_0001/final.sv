module bcd_counter (
    input  logic       clk,
    input  logic       rst,
    output logic [3:0] ms_hr,
    output logic [3:0] ls_hr,
    output logic [3:0] ms_min,
    output logic [3:0] ls_min,
    output logic [3:0] ms_sec,
    output logic [3:0] ls_sec
);

    logic [3:0] r_ls_sec;
    logic [2:0] r_ms_sec;
    logic [3:0] r_ls_min;
    logic [2:0] r_ms_min;
    logic [3:0] r_ls_hr;
    logic [1:0] r_ms_hr;

    logic en_ms_sec;
    logic en_ls_min;
    logic en_ms_min;
    logic en_hr;

    assign en_ms_sec = r_ls_sec[3] & r_ls_sec[0];
    assign en_ls_min = en_ms_sec & r_ms_sec[2] & r_ms_sec[0];
    assign en_ms_min = en_ls_min & r_ls_min[3] & r_ls_min[0];
    assign en_hr     = en_ms_min & r_ms_min[2] & r_ms_min[0];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            r_ls_sec <= 4'd0;
            r_ms_sec <= 3'd0;
            r_ms_min <= 3'd0;
        end else begin
            r_ls_sec[0] <= ~r_ls_sec[0];
            r_ls_sec[1] <= ~r_ls_sec[3] & (r_ls_sec[1] ^ r_ls_sec[0]);
            r_ls_sec[2] <= r_ls_sec[2] ^ (r_ls_sec[1] & r_ls_sec[0]);
            r_ls_sec[3] <= (r_ls_sec[3] & ~r_ls_sec[0]) | (r_ls_sec[2] & r_ls_sec[1] & r_ls_sec[0]);

            r_ms_sec[0] <= r_ms_sec[0] ^ en_ms_sec;
            r_ms_sec[1] <= r_ms_sec[1] ^ (~r_ms_sec[2] & r_ms_sec[0] & en_ms_sec);
            r_ms_sec[2] <= r_ms_sec[2] ^ ((r_ms_sec[2] | r_ms_sec[1]) & r_ms_sec[0] & en_ms_sec);

            r_ms_min[0] <= r_ms_min[0] ^ en_ms_min;
            r_ms_min[1] <= r_ms_min[1] ^ (~r_ms_min[2] & r_ms_min[0] & en_ms_min);
            r_ms_min[2] <= r_ms_min[2] ^ ((r_ms_min[2] | r_ms_min[1]) & r_ms_min[0] & en_ms_min);
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            r_ls_min <= 4'd0;
        end else if (en_ls_min) begin
            r_ls_min[0] <= ~r_ls_min[0];
            r_ls_min[1] <= ~r_ls_min[3] & (r_ls_min[1] ^ r_ls_min[0]);
            r_ls_min[2] <= r_ls_min[2] ^ (r_ls_min[1] & r_ls_min[0]);
            r_ls_min[3] <= (r_ls_min[3] & ~r_ls_min[0]) | (r_ls_min[2] & r_ls_min[1] & r_ls_min[0]);
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            r_ls_hr <= 4'd0;
            r_ms_hr <= 2'd0;
        end else if (en_hr) begin
            r_ls_hr[0] <= ~r_ls_hr[0];
            r_ls_hr[1] <= ~r_ls_hr[3] & (r_ls_hr[1] ^ r_ls_hr[0]);
            r_ls_hr[2] <= r_ls_hr[2] ^ (~r_ms_hr[1] & r_ls_hr[1] & r_ls_hr[0]);
            r_ls_hr[3] <= (r_ls_hr[3] & ~r_ls_hr[0]) | (r_ls_hr[2] & r_ls_hr[1] & r_ls_hr[0]);
            r_ms_hr[0] <= ~r_ms_hr[1] & (r_ms_hr[0] ^ (r_ls_hr[3] & r_ls_hr[0]));
            r_ms_hr[1] <= (r_ms_hr[0] & r_ls_hr[3] & r_ls_hr[0]) | (r_ms_hr[1] & ~(r_ls_hr[1] & r_ls_hr[0]));
        end
    end

    assign ls_sec = r_ls_sec;
    assign ms_sec = {1'b0, r_ms_sec};
    assign ls_min = r_ls_min;
    assign ms_min = {1'b0, r_ms_min};
    assign ls_hr  = r_ls_hr;
    assign ms_hr  = {2'b00, r_ms_hr};

endmodule
