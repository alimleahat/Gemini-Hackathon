module TopModule (
    input  logic clk,
    input  logic areset,
    input  logic bump_left,
    input  logic bump_right,
    input  logic ground,
    input  logic dig,
    output logic walk_left,
    output logic walk_right,
    output logic aaah,
    output logic digging
);

    typedef enum logic [2:0] {
        WALK_L,
        WALK_R,
        FALL_L,
        FALL_R,
        DIG_L,
        DIG_R,
        SPLAT
    } state_t;

    state_t state, next_state;
    logic [4:0] fall_cnt;

    always_comb begin
        next_state = state;
        case (state)
            WALK_L: begin
                if (!ground)
                    next_state = FALL_L;
                else if (dig)
                    next_state = DIG_L;
                else if (bump_left)
                    next_state = WALK_R;
                else
                    next_state = WALK_L;
            end
            WALK_R: begin
                if (!ground)
                    next_state = FALL_R;
                else if (dig)
                    next_state = DIG_R;
                else if (bump_right)
                    next_state = WALK_L;
                else
                    next_state = WALK_R;
            end
            FALL_L: begin
                if (ground)
                    next_state = (fall_cnt >= 5'd20) ? SPLAT : WALK_L;
                else
                    next_state = FALL_L;
            end
            FALL_R: begin
                if (ground)
                    next_state = (fall_cnt >= 5'd20) ? SPLAT : WALK_R;
                else
                    next_state = FALL_R;
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
            SPLAT: begin
                next_state = SPLAT;
            end
            default: begin
                next_state = WALK_L;
            end
        endcase
    end

    always_ff @(posedge clk or posedge areset) begin
        if (areset) begin
            state <= WALK_L;
            fall_cnt <= 5'd0;
        end else begin
            state <= next_state;
            if (state == FALL_L || state == FALL_R) begin
                if (!ground && fall_cnt < 5'd20)
                    fall_cnt <= fall_cnt + 5'd1;
                else if (ground)
                    fall_cnt <= 5'd0;
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
