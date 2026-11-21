module sorting_engine #(
    parameter int N     = 8,
    parameter int WIDTH = 8
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 start,
    input  logic [N*WIDTH-1:0]   in_data,
    output logic                 done,
    output logic [N*WIDTH-1:0]   out_data
);

    typedef enum logic [1:0] {
        IDLE    = 2'd0,
        SORTING = 2'd1,
        DONE    = 2'd2
    } state_t;

    state_t state;
    logic [WIDTH-1:0] arr [0:N-1];

    generate
        if (N > 1) begin : gen_multi
            localparam int CNT_W = $clog2(N + 1);
            localparam int IDX_W = (N > 2) ? $clog2(N - 1) : 1;
            localparam [CNT_W-1:0] PASS_LIMIT = N;
            localparam [IDX_W-1:0] IDX_LIMIT  = (N > 2) ? (N - 2) : 0;

            logic [CNT_W-1:0] pass_cnt;
            logic [IDX_W-1:0] idx;

            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    state    <= IDLE;
                    done     <= 1'b0;
                    pass_cnt <= '0;
                    idx      <= '0;
                    for (int k = 0; k < N; k = k + 1) begin
                        arr[k] <= '0;
                    end
                end else begin
                    case (state)
                        IDLE: begin
                            done <= 1'b0;
                            if (start) begin
                                for (int k = 0; k < N; k = k + 1) begin
                                    arr[k] <= in_data[k*WIDTH +: WIDTH];
                                end
                                pass_cnt <= '0;
                                idx      <= '0;
                                state    <= SORTING;
                            end
                        end

                        SORTING: begin
                            done <= 1'b0;
                            if (pass_cnt < PASS_LIMIT) begin
                                if (arr[idx] > arr[idx + 1]) begin
                                    arr[idx]     <= arr[idx + 1];
                                    arr[idx + 1] <= arr[idx];
                                end

                                if (idx < IDX_LIMIT) begin
                                    idx <= idx + 1'b1;
                                end else begin
                                    idx      <= '0;
                                    pass_cnt <= pass_cnt + 1'b1;
                                end
                            end else begin
                                state <= DONE;
                                done  <= 1'b1;
                            end
                        end

                        DONE: begin
                            done  <= 1'b0;
                            state <= IDLE;
                        end

                        default: begin
                            done  <= 1'b0;
                            state <= IDLE;
                        end
                    endcase
                end
            end

            always_ff @(posedge clk) begin
                if (!rst && (state == SORTING) && (pass_cnt == PASS_LIMIT)) begin
                    for (int k = 0; k < N; k = k + 1) begin
                        out_data[k*WIDTH +: WIDTH] <= arr[k];
                    end
                end
            end
        end else begin : gen_single
            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    state  <= IDLE;
                    done   <= 1'b0;
                    arr[0] <= '0;
                end else begin
                    case (state)
                        IDLE: begin
                            done <= 1'b0;
                            if (start) begin
                                arr[0] <= in_data[WIDTH-1:0];
                                state  <= SORTING;
                            end
                        end

                        SORTING: begin
                            state <= DONE;
                            done  <= 1'b1;
                        end

                        DONE: begin
                            done  <= 1'b0;
                            state <= IDLE;
                        end

                        default: begin
                            done  <= 1'b0;
                            state <= IDLE;
                        end
                    endcase
                end
            end

            always_ff @(posedge clk) begin
                if (!rst && (state == SORTING)) begin
                    out_data[WIDTH-1:0] <= arr[0];
                end
            end
        end
    endgenerate

endmodule
