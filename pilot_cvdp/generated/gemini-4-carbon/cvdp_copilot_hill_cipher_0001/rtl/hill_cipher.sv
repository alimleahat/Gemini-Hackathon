module hill_cipher (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [14:0] plaintext,
    input  logic [44:0] key,
    output logic [14:0] ciphertext,
    output logic        done
);

    typedef enum logic [1:0] {
        S_IDLE = 2'd0,
        S_MULT = 2'd1,
        S_MOD  = 2'd2
    } state_t;

    state_t state;

    logic [4:0]  p0, p1, p2;
    logic [4:0]  k00, k01, k02;
    logic [4:0]  k10, k11, k12;
    logic [4:0]  k20, k21, k22;
    logic [11:0] sum0, sum1, sum2;

    function automatic logic [4:0] mod26(input logic [11:0] val);
        logic [11:0] rem;
        begin
            rem   = val % 12'd26;
            mod26 = rem[4:0];
        end
    endfunction

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state      <= S_IDLE;
            p0         <= 5'd0;
            p1         <= 5'd0;
            p2         <= 5'd0;
            k00        <= 5'd0;
            k01        <= 5'd0;
            k02        <= 5'd0;
            k10        <= 5'd0;
            k11        <= 5'd0;
            k12        <= 5'd0;
            k20        <= 5'd0;
            k21        <= 5'd0;
            k22        <= 5'd0;
            sum0       <= 12'd0;
            sum1       <= 12'd0;
            sum2       <= 12'd0;
            ciphertext <= 15'd0;
            done       <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        p0    <= plaintext[14:10];
                        p1    <= plaintext[9:5];
                        p2    <= plaintext[4:0];
                        k00   <= key[44:40];
                        k01   <= key[39:35];
                        k02   <= key[34:30];
                        k10   <= key[29:25];
                        k11   <= key[24:20];
                        k12   <= key[19:15];
                        k20   <= key[14:10];
                        k21   <= key[9:5];
                        k22   <= key[4:0];
                        state <= S_MULT;
                    end
                end

                S_MULT: begin
                    done  <= 1'b0;
                    sum0  <= ({7'd0, k00} * {7'd0, p0}) + ({7'd0, k01} * {7'd0, p1}) + ({7'd0, k02} * {7'd0, p2});
                    sum1  <= ({7'd0, k10} * {7'd0, p0}) + ({7'd0, k11} * {7'd0, p1}) + ({7'd0, k12} * {7'd0, p2});
                    sum2  <= ({7'd0, k20} * {7'd0, p0}) + ({7'd0, k21} * {7'd0, p1}) + ({7'd0, k22} * {7'd0, p2});
                    state <= S_MOD;
                end

                S_MOD: begin
                    ciphertext <= {mod26(sum0), mod26(sum1), mod26(sum2)};
                    done       <= 1'b1;
                    state      <= S_IDLE;
                end

                default: begin
                    done  <= 1'b0;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
