module hill_cipher (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [14:0] plaintext,
    input  logic [44:0] key,
    output logic [14:0] ciphertext,
    output logic        done
);

    logic        st0, st1;
    logic        en_cap, en_out;
    logic [14:0] res_r;

    logic [4:0]  p0, p1, p2;
    logic [4:0]  k00, k01, k02;
    logic [4:0]  k10, k11, k12;
    logic [4:0]  k20, k21, k22;

    logic [11:0] sum0, sum1, sum2;

    assign p0  = plaintext[14:10];
    assign p1  = plaintext[9:5];
    assign p2  = plaintext[4:0];

    assign k00 = key[44:40];
    assign k01 = key[39:35];
    assign k02 = key[34:30];
    assign k10 = key[29:25];
    assign k11 = key[24:20];
    assign k12 = key[19:15];
    assign k20 = key[14:10];
    assign k21 = key[9:5];
    assign k22 = key[4:0];

    assign sum0 = ({7'd0, k00} * {7'd0, p0}) + ({7'd0, k01} * {7'd0, p1}) + ({7'd0, k02} * {7'd0, p2});
    assign sum1 = ({7'd0, k10} * {7'd0, p0}) + ({7'd0, k11} * {7'd0, p1}) + ({7'd0, k12} * {7'd0, p2});
    assign sum2 = ({7'd0, k20} * {7'd0, p0}) + ({7'd0, k21} * {7'd0, p1}) + ({7'd0, k22} * {7'd0, p2});

    function automatic logic [4:0] mod26(input logic [11:0] val);
        logic [10:0] y;
        logic [17:0] q_prod;
        logic [3:0]  q_lo;
        logic [3:0]  t;
        logic [3:0]  rem13;
        begin
            y      = val[11:1];
            q_prod = {7'd0, y} * 18'd1261;
            q_lo   = q_prod[17:14];
            case (q_lo)
                4'd0:  t = 4'd0;
                4'd1:  t = 4'd3;
                4'd2:  t = 4'd6;
                4'd3:  t = 4'd9;
                4'd4:  t = 4'd12;
                4'd5:  t = 4'd15;
                4'd6:  t = 4'd2;
                4'd7:  t = 4'd5;
                4'd8:  t = 4'd8;
                4'd9:  t = 4'd11;
                4'd10: t = 4'd14;
                4'd11: t = 4'd1;
                4'd12: t = 4'd4;
                4'd13: t = 4'd7;
                4'd14: t = 4'd10;
                4'd15: t = 4'd13;
            endcase
            rem13 = y[3:0] + t;
            mod26 = {rem13, val[0]};
        end
    endfunction

    assign en_cap = ~st1 & start;
    assign en_out =  st1 & st0;
    assign done   = ~st1 & st0;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            st0        <= 1'b0;
            st1        <= 1'b0;
            res_r      <= 15'd0;
            ciphertext <= 15'd0;
        end else begin
            st0 <= st1;
            st1 <= en_cap | (st1 & ~st0);
            if (en_cap) begin
                res_r <= {mod26(sum0), mod26(sum1), mod26(sum2)};
            end
            if (en_out) begin
                ciphertext <= res_r;
            end
        end
    end

endmodule
