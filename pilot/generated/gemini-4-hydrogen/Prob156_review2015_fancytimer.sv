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
        S     = 4'd0,
        S1    = 4'd1,
        S11   = 4'd2,
        S110  = 4'd3,
        B0    = 4'd4,
        B1    = 4'd5,
        B2    = 4'd6,
        B3    = 4'd7,
        COUNT = 4'd8,
        WAIT  = 4'd9
    } state_t;

    state_t state, next_state;
    logic [3:0] delay;
    logic [9:0] sub_cnt;

    always_comb begin
        next_state = S;
        case (state)
            S:     next_state = data ? S1 : S;
            S1:    next_state = data ? S11 : S;
            S11:   next_state = data ? S11 : S110;
            S110:  next_state = data ? B0 : S;
            B0:    next_state = B1;
            B1:    next_state = B2;
            B2:    next_state = B3;
            B3:    next_state = COUNT;
            COUNT: next_state = (sub_cnt == 10'd999 && delay == 4'd0) ? WAIT : COUNT;
            WAIT:  next_state = ack ? S : WAIT;
            default: next_state = S;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state   <= S;
            delay   <= 4'd0;
            sub_cnt <= 10'd0;
        end else begin
            state <= next_state;
            case (state)
                B0, B1, B2: begin
                    delay <= {delay[2:0], data};
                end
                B3: begin
                    delay   <= {delay[2:0], data};
                    sub_cnt <= 10'd0;
                end
                COUNT: begin
                    if (sub_cnt == 10'd999) begin
                        sub_cnt <= 10'd0;
                        if (delay != 4'd0) begin
                            delay <= delay - 4'd1;
                        end
                    end else begin
                        sub_cnt <= sub_cnt + 10'd1;
                    end
                end
                default: ;
            endcase
        end
    end

    assign counting = (state == COUNT);
    assign done     = (state == WAIT);
    assign count    = delay;

endmodule
