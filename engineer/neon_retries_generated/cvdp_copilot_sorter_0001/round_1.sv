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

    localparam int CNT_W = (N > 1) ? $clog2(N) : 1;
    localparam [CNT_W-1:0] ZERO      = 0;
    localparam [CNT_W-1:0] ONE       = 1;
    localparam [CNT_W-1:0] LAST_PASS = N - 1;
    localparam [CNT_W-1:0] LAST_IDX  = (N > 1) ? (N - 2) : 0;

    state_t           state;
    logic [WIDTH-1:0] arr [0:N-1];
    logic [CNT_W-1:0] pass_cnt;
    logic [CNT_W-1:0] idx_cnt;

    generate
        if (N == 1) begin : gen_single
            always_ff @(posedge clk or posedge rst) begin : fsm_single_proc
                if (rst) begin
                    state    <= IDLE;
                    done     <= 1'b0;
                    pass_cnt <= ZERO;
                    idx_cnt  <= ZERO;
                    arr[0]   <= {WIDTH{1'b0}};
                end else begin
                    case (state)
                        IDLE: begin
                            done <= 1'b0;
                            if (start) begin
                                arr[0] <= in_data[WIDTH-1:0];
                                state  <= DONE;
                            end
                        end

                        SORTING: begin
                            done  <= 1'b0;
                            state <= DONE;
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
            always_ff @(posedge clk or posedge rst) begin : fsm_multi_proc
                integer k;
                if (rst) begin
                    state    <= IDLE;
                    done     <= 1'b0;
                    pass_cnt <= ZERO;
                    idx_cnt  <= ZERO;
                    for (k = 0; k < N; k = k + 1) begin
                        arr[k] <= {WIDTH{1'b0}};
                    end
                end else begin
                    case (state)
                        IDLE: begin
                            done <= 1'b0;
                            if (start) begin
                                for (k = 0; k < N; k = k + 1) begin
                                    arr[k] <= in_data[k*WIDTH +: WIDTH];
                                end
                                pass_cnt <= ZERO;
                                idx_cnt  <= ZERO;
                                state    <= SORTING;
                            end
                        end

                        SORTING: begin
                            done <= 1'b0;
                            if (arr[idx_cnt] > arr[idx_cnt + ONE]) begin
                                arr[idx_cnt]       <= arr[idx_cnt + ONE];
                                arr[idx_cnt + ONE] <= arr[idx_cnt];
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
                                idx_cnt <= idx_cnt + ONE;
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
        integer k;
        if (!rst && (state == DONE)) begin
            for (k = 0; k < N; k = k + 1) begin
                out_data[k*WIDTH +: WIDTH] <= arr[k];
            end
        end
    end

endmodule
