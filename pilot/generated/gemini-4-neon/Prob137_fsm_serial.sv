module TopModule (
    input  clk,
    input  reset,
    input  in,
    output done
);

    localparam [3:0] IDLE = 4'd0,
                     BIT0 = 4'd1,
                     BIT1 = 4'd2,
                     BIT2 = 4'd3,
                     BIT3 = 4'd4,
                     BIT4 = 4'd5,
                     BIT5 = 4'd6,
                     BIT6 = 4'd7,
                     BIT7 = 4'd8,
                     STOP = 4'd9,
                     DONE = 4'd10,
                     WAIT = 4'd11;

    reg [3:0] state, next_state;

    always @(*) begin
        case (state)
            IDLE: next_state = in ? IDLE : BIT0;
            BIT0: next_state = BIT1;
            BIT1: next_state = BIT2;
            BIT2: next_state = BIT3;
            BIT3: next_state = BIT4;
            BIT4: next_state = BIT5;
            BIT5: next_state = BIT6;
            BIT6: next_state = BIT7;
            BIT7: next_state = STOP;
            STOP: next_state = in ? DONE : WAIT;
            DONE: next_state = in ? IDLE : BIT0;
            WAIT: next_state = in ? IDLE : WAIT;
            default: next_state = IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    assign done = (state == DONE);

endmodule
