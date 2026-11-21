module TopModule (
    input  clk,
    input  areset,
    input  bump_left,
    input  bump_right,
    input  ground,
    input  dig,
    output walk_left,
    output walk_right,
    output aaah,
    output digging
);

    localparam [2:0]
        WALK_L = 3'd0,
        WALK_R = 3'd1,
        FALL_L = 3'd2,
        FALL_R = 3'd3,
        DIG_L  = 3'd4,
        DIG_R  = 3'd5,
        SPLAT  = 3'd6;

    reg [2:0] state, next_state;
    reg [4:0] fall_cnt;

    always @(*) begin
        next_state = state;
        case (state)
            WALK_L: begin
                if (!ground)         next_state = FALL_L;
                else if (dig)        next_state = DIG_L;
                else if (bump_left)  next_state = WALK_R;
                else                 next_state = WALK_L;
            end
            WALK_R: begin
                if (!ground)         next_state = FALL_R;
                else if (dig)        next_state = DIG_R;
                else if (bump_right) next_state = WALK_L;
                else                 next_state = WALK_R;
            end
            FALL_L: begin
                if (!ground)                   next_state = FALL_L;
                else if (fall_cnt >= 5'd20)    next_state = SPLAT;
                else                           next_state = WALK_L;
            end
            FALL_R: begin
                if (!ground)                   next_state = FALL_R;
                else if (fall_cnt >= 5'd20)    next_state = SPLAT;
                else                           next_state = WALK_R;
            end
            DIG_L: begin
                if (!ground) next_state = FALL_L;
                else         next_state = DIG_L;
            end
            DIG_R: begin
                if (!ground) next_state = FALL_R;
                else         next_state = DIG_R;
            end
            SPLAT: begin
                next_state = SPLAT;
            end
            default: begin
                next_state = WALK_L;
            end
        endcase
    end

    always @(posedge clk or posedge areset) begin
        if (areset) begin
            state    <= WALK_L;
            fall_cnt <= 5'd0;
        end else begin
            state <= next_state;
            if ((state == FALL_L || state == FALL_R) && !ground) begin
                if (fall_cnt < 5'd20)
                    fall_cnt <= fall_cnt + 5'd1;
            end else begin
                fall_cnt <= 5'd0;
            end
        end
    end

    assign walk_left  = (state == WALK_L);
    assign walk_right = (state == WALK_R);
    assign aaah       = (state == FALL_L) || (state == FALL_R);
    assign digging    = (state == DIG_L)  || (state == DIG_R);

endmodule
