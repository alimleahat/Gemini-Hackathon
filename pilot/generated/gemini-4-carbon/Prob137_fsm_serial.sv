module TopModule (
    input  wire clk,
    input  wire reset,
    input  wire in,
    output wire done
);

    typedef enum logic [3:0] {
        IDLE,
        BIT0,
        BIT1,
        BIT2,
        BIT3,
        BIT4,
        BIT5,
        BIT6,
        BIT7,
        STOP,
        DONE,
        WAIT
    } state_t;

    state_t state, next_state;

    always_comb begin
        case (state)
            IDLE:    next_state = in ? IDLE : BIT0;
            BIT0:    next_state = BIT1;
            BIT1:    next_state = BIT2;
            BIT2:    next_state = BIT3;
            BIT3:    next_state = BIT4;
            BIT4:    next_state = BIT5;
            BIT5:    next_state = BIT6;
            BIT6:    next_state = BIT7;
            BIT7:    next_state = STOP;
            STOP:    next_state = in ? DONE : WAIT;
            DONE:    next_state = in ? IDLE : BIT0;
            WAIT:    next_state = in ? IDLE : WAIT;
            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    assign done = (state == DONE);

endmodule
