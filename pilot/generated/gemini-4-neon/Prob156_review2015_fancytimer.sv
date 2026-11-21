module TopModule (
    input        clk,
    input        reset,
    input        data,
    output [3:0] count,
    output       counting,
    output       done,
    input        ack
);

    localparam [3:0]
        S     = 4'd0,
        S1    = 4'd1,
        S11   = 4'd2,
        S110  = 4'd3,
        B0    = 4'd4,
        B1    = 4'd5,
        B2    = 4'd6,
        B3    = 4'd7,
        COUNT = 4'd8,
        WAIT  = 4'd9;

    reg [3:0] state, next_state;
    reg [3:0] delay_reg;
    reg [9:0] sub_cnt;

    wire done_counting = (sub_cnt == 10'd999) && (delay_reg == 4'd0);

    always @(*) begin
        case (state)
            S:     next_state = data ? S1 : S;
            S1:    next_state = data ? S11 : S;
            S11:   next_state = data ? S11 : S110;
            S110:  next_state = data ? B0 : S;
            B0:    next_state = B1;
            B1:    next_state = B2;
            B2:    next_state = B3;
            B3:    next_state = COUNT;
            COUNT: next_state = done_counting ? WAIT : COUNT;
            WAIT:  next_state = ack ? S : WAIT;
            default: next_state = S;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            state     <= S;
            delay_reg <= 4'd0;
            sub_cnt   <= 10'd0;
        end else begin
            state <= next_state;

            if (state == B0 || state == B1 || state == B2 || state == B3) begin
                delay_reg <= {delay_reg[2:0], data};
                sub_cnt   <= 10'd0;
            end else if (state == COUNT) begin
                if (sub_cnt == 10'd999) begin
                    sub_cnt <= 10'd0;
                    if (delay_reg != 4'd0)
                        delay_reg <= delay_reg - 4'd1;
                end else begin
                    sub_cnt <= sub_cnt + 10'd1;
                end
            end else begin
                sub_cnt <= 10'd0;
            end
        end
    end

    assign count    = delay_reg;
    assign counting = (state == COUNT);
    assign done     = (state == WAIT);

endmodule
