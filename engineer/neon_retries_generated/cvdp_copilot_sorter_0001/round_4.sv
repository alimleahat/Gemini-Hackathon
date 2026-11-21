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
        IDLE    = 2'd0,
        SORTING = 2'd1,
        DONE    = 2'd2
    } state_t;

    state_t             state;
    logic [N*WIDTH-1:0] arr;

    generate
        if (N == 1) begin : gen_single
            always_ff @(posedge clk or posedge rst) begin : fsm_single_proc
                if (rst) begin
                    state <= IDLE;
                    done  <= 1'b0;
                    arr   <= {N*WIDTH{1'b0}};
                end else begin
                    case (state)
                        IDLE: begin
                            done <= 1'b0;
                            if (start) begin
                                arr   <= in_data;
                                state <= DONE;
                            end
                        end

                        DONE: begin
                            done  <= 1'b1;
                            state <= IDLE;
                        end

                        default: begin
                            done  <= 1'b0;
                            state <= IDLE;
                        end
                    endcase
                end
            end
        end else begin : gen_multi
            localparam int CNT_W             = (N > 1) ? $clog2(N) : 1;
            localparam [CNT_W-1:0] ZERO      = 0;
            localparam [CNT_W-1:0] ONE       = 1;
            localparam [CNT_W-1:0] LAST_PASS = N - 1;
            localparam [CNT_W-1:0] LAST_IDX  = N - 2;

            logic [CNT_W-1:0] pass_cnt;
            logic [CNT_W-1:0] idx_cnt;
            logic [CNT_W-1:0] idx_next;
            logic [WIDTH-1:0] elem_cur;
            logic [WIDTH-1:0] elem_nxt;

            assign idx_next = idx_cnt + ONE;

            always_comb begin : elem_mux_proc
                elem_cur = {WIDTH{1'b0}};
                elem_nxt = {WIDTH{1'b0}};
                for (int m = 0; m < N; m = m + 1) begin
                    if (m == idx_cnt) begin
                        elem_cur = arr[m*WIDTH +: WIDTH];
                    end
                    if (m == idx_next) begin
                        elem_nxt = arr[m*WIDTH +: WIDTH];
                    end
                end
            end

            always_ff @(posedge clk or posedge rst) begin : fsm_multi_proc
                if (rst) begin
                    state    <= IDLE;
                    done     <= 1'b0;
                    pass_cnt <= ZERO;
                    idx_cnt  <= ZERO;
                    arr      <= {N*WIDTH{1'b0}};
                end else begin
                    case (state)
                        IDLE: begin
                            done <= 1'b0;
                            if (start) begin
                                arr      <= in_data;
                                pass_cnt <= ZERO;
                                idx_cnt  <= ZERO;
                                state    <= SORTING;
                            end
                        end

                        SORTING: begin
                            done <= 1'b0;
                            if (elem_cur > elem_nxt) begin
                                for (int k = 0; k < N; k = k + 1) begin
                                    if (k == idx_cnt) begin
                                        arr[k*WIDTH +: WIDTH] <= elem_nxt;
                                    end else if (k == idx_next) begin
                                        arr[k*WIDTH +: WIDTH] <= elem_cur;
                                    end
                                end
                            end

                            if (idx_cnt == LAST_IDX) begin
                                idx_cnt <= ZERO;
                                if (pass_cnt == LAST_PASS) begin
                                    pass_cnt <= ZERO;
                                    state    <= DONE;
                                end else begin
                                    pass_cnt <= pass_cnt + ONE;
                                end
                            end else begin
                                idx_cnt <= idx_next;
                            end
                        end

                        DONE: begin
                            done  <= 1'b1;
                            state <= IDLE;
                        end

                        default: begin
                            done  <= 1'b0;
                            state <= IDLE;
                        end
                    endcase
                end
            end
        end
    endgenerate

    always_ff @(posedge clk) begin : out_proc
        if (!rst && (state == DONE)) begin
            out_data <= arr;
        end
    end

endmodule
