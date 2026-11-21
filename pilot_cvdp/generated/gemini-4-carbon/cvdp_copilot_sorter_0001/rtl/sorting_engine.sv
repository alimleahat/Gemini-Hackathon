module sorting_engine #(
    parameter int N     = 8,
    parameter int WIDTH = 8
) (
    input  logic               clk,
    input  logic               rst,
    input  logic               start,
    input  logic [N*WIDTH-1:0] in_data,
    output logic               done,
    output logic [N*WIDTH-1:0] out_data
);

    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        SORTING = 2'b01,
        DONE    = 2'b10
    } state_t;

    state_t state, next_state;

    generate
        if (N == 1) begin : gen_single_elem
            logic [WIDTH-1:0] elem;

            always_comb begin
                next_state = state;
                case (state)
                    IDLE: begin
                        if (start)
                            next_state = DONE;
                    end
                    DONE: begin
                        next_state = IDLE;
                    end
                    default: begin
                        next_state = IDLE;
                    end
                endcase
            end

            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    state <= IDLE;
                    done  <= 1'b0;
                    elem  <= '0;
                end else begin
                    state <= next_state;
                    case (state)
                        IDLE: begin
                            done <= 1'b0;
                            if (start)
                                elem <= in_data;
                        end
                        DONE: begin
                            done <= 1'b1;
                        end
                        default: begin
                            done <= 1'b0;
                        end
                    endcase
                end
            end

            always_ff @(posedge clk) begin
                if (!rst && (state == DONE)) begin
                    out_data <= elem;
                end
            end
        end else begin : gen_multi_elem
            localparam int IDX_W = $clog2(N);
            localparam logic [IDX_W-1:0] LAST_I = N - 1;
            localparam logic [IDX_W-1:0] LAST_J = N - 2;

            logic [WIDTH-1:0] array [0:N-1];
            logic [IDX_W-1:0] pass_cnt;
            logic [IDX_W-1:0] comp_cnt;

            integer k;
            integer m;

            always_comb begin
                next_state = state;
                case (state)
                    IDLE: begin
                        if (start)
                            next_state = SORTING;
                    end
                    SORTING: begin
                        if ((pass_cnt == LAST_I) && (comp_cnt == LAST_J))
                            next_state = DONE;
                    end
                    DONE: begin
                        next_state = IDLE;
                    end
                    default: begin
                        next_state = IDLE;
                    end
                endcase
            end

            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    state    <= IDLE;
                    done     <= 1'b0;
                    pass_cnt <= '0;
                    comp_cnt <= '0;
                    for (k = 0; k < N; k = k + 1) begin
                        array[k] <= '0;
                    end
                end else begin
                    state <= next_state;
                    case (state)
                        IDLE: begin
                            done     <= 1'b0;
                            pass_cnt <= '0;
                            comp_cnt <= '0;
                            if (start) begin
                                for (k = 0; k < N; k = k + 1) begin
                                    array[k] <= in_data[k*WIDTH +: WIDTH];
                                end
                            end
                        end

                        SORTING: begin
                            done <= 1'b0;
                            if (array[comp_cnt] > array[comp_cnt + 1'b1]) begin
                                array[comp_cnt]        <= array[comp_cnt + 1'b1];
                                array[comp_cnt + 1'b1] <= array[comp_cnt];
                            end

                            if (comp_cnt == LAST_J) begin
                                comp_cnt <= '0;
                                if (pass_cnt == LAST_I)
                                    pass_cnt <= '0;
                                else
                                    pass_cnt <= pass_cnt + 1'b1;
                            end else begin
                                comp_cnt <= comp_cnt + 1'b1;
                            end
                        end

                        DONE: begin
                            done <= 1'b1;
                        end

                        default: begin
                            done <= 1'b0;
                        end
                    endcase
                end
            end

            always_ff @(posedge clk) begin
                if (!rst && (state == DONE)) begin
                    for (m = 0; m < N; m = m + 1) begin
                        out_data[m*WIDTH +: WIDTH] <= array[m];
                    end
                end
            end
        end
    endgenerate

endmodule
