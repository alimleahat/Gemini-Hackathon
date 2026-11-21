module TopModule (
    input  logic clk,
    input  logic reset,
    input  logic in,
    output logic done
);

    typedef enum logic [2:0] {
        IDLE = 3'd0,
        DATA = 3'd1,
        STOP = 3'd2,
        DONE = 3'd3,
        WAIT = 3'd4
    } state_t;

    state_t state, next_state;
    logic [2:0] bit_cnt;

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (!in)
                    next_state = DATA;
            end
            DATA: begin
                if (bit_cnt == 3'd7)
                    next_state = STOP;
            end
            STOP: begin
                if (in)
                    next_state = DONE;
                else
                    next_state = WAIT;
            end
            DONE: begin
                if (!in)
                    next_state = DATA;
                else
                    next_state = IDLE;
            end
            WAIT: begin
                if (in)
                    next_state = IDLE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state   <= IDLE;
            bit_cnt <= 3'd0;
        end else begin
            state <= next_state;
            if (state == DATA)
                bit_cnt <= bit_cnt + 3'd1;
            else
                bit_cnt <= 3'd0;
        end
    end

    assign done = (state == DONE);

endmodule
