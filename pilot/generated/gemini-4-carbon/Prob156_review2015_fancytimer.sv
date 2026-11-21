module TopModule (
    input  logic       clk,
    input  logic       reset,
    input  logic       data,
    output logic [3:0] count,
    output logic       counting,
    output logic       done,
    input  logic       ack
);

    typedef enum logic [3:0] {
        S_IDLE  = 4'd0,
        S_1     = 4'd1,
        S_11    = 4'd2,
        S_110   = 4'd3,
        S_B0    = 4'd4,
        S_B1    = 4'd5,
        S_B2    = 4'd6,
        S_B3    = 4'd7,
        S_COUNT = 4'd8,
        S_DONE  = 4'd9
    } state_t;

    state_t state, next_state;
    logic [9:0] sub_cnt;

    always_comb begin
        next_state = state;
        case (state)
            S_IDLE:  next_state = data ? S_1 : S_IDLE;
            S_1:     next_state = data ? S_11 : S_IDLE;
            S_11:    next_state = data ? S_11 : S_110;
            S_110:   next_state = data ? S_B0 : S_IDLE;
            S_B0:    next_state = S_B1;
            S_B1:    next_state = S_B2;
            S_B2:    next_state = S_B3;
            S_B3:    next_state = S_COUNT;
            S_COUNT: begin
                if (count == 4'd0 && sub_cnt == 10'd999)
                    next_state = S_DONE;
                else
                    next_state = S_COUNT;
            end
            S_DONE:  next_state = ack ? S_IDLE : S_DONE;
            default: next_state = S_IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state   <= S_IDLE;
            count   <= 4'd0;
            sub_cnt <= 10'd0;
        end else begin
            state <= next_state;

            case (state)
                S_B0, S_B1, S_B2, S_B3: begin
                    count   <= {count[2:0], data};
                    sub_cnt <= 10'd0;
                end
                S_COUNT: begin
                    if (sub_cnt == 10'd999) begin
                        sub_cnt <= 10'd0;
                        if (count != 4'd0)
                            count <= count - 4'd1;
                    end else begin
                        sub_cnt <= sub_cnt + 10'd1;
                    end
                end
                default: begin
                    sub_cnt <= 10'd0;
                end
            endcase
        end
    end

    assign counting = (state == S_COUNT);
    assign done     = (state == S_DONE);

endmodule
