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
        LEFT   = 3'd0,
        RIGHT  = 3'd1,
        FALL_L = 3'd2,
        FALL_R = 3'd3,
        DIG_L  = 3'd4,
        DIG_R  = 3'd5,
        SPLAT  = 3'd6;

    reg [2:0] state, next_state;
    reg [4:0] fall_cnt;

    always @(*) begin
        case (state)
            LEFT: begin
                if (!ground)
                    next_state = FALL_L;
                else if (dig)
                    next_state = DIG_L;
                else if (bump_left)
                    next_state = RIGHT;
                else
                    next_state = LEFT;
            end
            RIGHT: begin
                if (!ground)
                    next_state = FALL_R;
                else if (dig)
                    next_state = DIG_R;
                else if (bump_right)
                    next_state = LEFT;
                else
                    next_state = RIGHT;
            end
            DIG_L: begin
                if (!ground)
                    next_state = FALL_L;
                else
                    next_state = DIG_L;
            end
            DIG_R: begin
                if (!ground)
                    next_state = FALL_R;
                else
                    next_state = DIG_R;
            end
            FALL_L: begin
                if (ground)
                    next_state = (fall_cnt >= 5'd20) ? SPLAT : LEFT;
                else
                    next_state = FALL_L;
            end
            FALL_R: begin
                if (ground)
                    next_state = (fall_cnt >= 5'd20) ? SPLAT : RIGHT;
                else
                    next_state = FALL_R;
            end
            SPLAT: begin
                next_state = SPLAT;
            end
            default: begin
                next_state = LEFT;
            end
        endcase
    end

    always @(posedge clk or posedge areset) begin
        if (areset) begin
            state    <= LEFT;
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

    assign walk_left  = (state == LEFT);
    assign walk_right = (state == RIGHT);
    assign aaah       = (state == FALL_L) || (state == FALL_R);
    assign digging    = (state == DIG_L)  || (state == DIG_R);

endmodule
