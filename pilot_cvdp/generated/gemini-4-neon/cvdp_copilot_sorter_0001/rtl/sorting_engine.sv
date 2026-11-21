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

    state_t           state;
    logic [WIDTH-1:0] arr [0:N-1];
    logic             load_out;

    generate
        if (N == 1) begin : gen_single
            assign load_out = (state == SORTING);

            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    state  <= IDLE;
                    done   <= 1'b0;
                    arr[0] <= '0;
                end else begin
                    done <= 1'b0;
                    case (state)
                        IDLE: begin
                            if (start) begin
                                arr[0] <= in_data;
                                state  <= SORTING;
                            end
                        end

                        SORTING: begin
                            state <= DONE;
                            done  <= 1'b1;
                        end

                        DONE: begin
                            if (start) begin
                                arr[0] <= in_data;
                                state  <= SORTING;
                            end else begin
                                state  <= IDLE;
                            end
                        end

                        default: begin
                            state <= IDLE;
                        end
                    endcase
                end
            end
        end else begin : gen_multi
            localparam int CNT_W = $clog2(N + 1);
            localparam logic [CNT_W-1:0] N_LIMIT = N;
            localparam logic [CNT_W-1:0] J_LAST  = N - 2;

            logic [CNT_W-1:0] i_cnt;
            logic [CNT_W-1:0] j_cnt;

            assign load_out = (state == SORTING) && (i_cnt == N_LIMIT);

            always_ff @(posedge clk or posedge rst) begin : fsm_proc
                integer k;
                if (rst) begin
                    state <= IDLE;
                    done  <= 1'b0;
                    i_cnt <= '0;
                    j_cnt <= '0;
                    for (k = 0; k < N; k = k + 1) begin
                        arr[k] <= '0;
                    end
                end else begin
                    done <= 1'b0;
                    case (state)
                        IDLE: begin
                            if (start) begin
                                for (k = 0; k < N; k = k + 1) begin
                                    arr[k] <= in_data[k*WIDTH +: WIDTH];
                                end
                                i_cnt <= '0;
                                j_cnt <= '0;
                                state <= SORTING;
                            end
                        end

                        SORTING: begin
                            if (i_cnt < N_LIMIT) begin
                                if (arr[j_cnt] > arr[j_cnt + 1'b1]) begin
                                    arr[j_cnt]        <= arr[j_cnt + 1'b1];
                                    arr[j_cnt + 1'b1] <= arr[j_cnt];
                                end
                                if (j_cnt == J_LAST) begin
                                    j_cnt <= '0;
                                    i_cnt <= i_cnt + 1'b1;
                                end else begin
                                    j_cnt <= j_cnt + 1'b1;
                                end
                            end else begin
                                state <= DONE;
                                done  <= 1'b1;
                            end
                        end

                        DONE: begin
                            if (start) begin
                                for (k = 0; k < N; k = k + 1) begin
                                    arr[k] <= in_data[k*WIDTH +: WIDTH];
                                end
                                i_cnt <= '0;
                                j_cnt <= '0;
                                state <= SORTING;
                            end else begin
                                state <= IDLE;
                            end
                        end

                        default: begin
                            state <= IDLE;
                        end
                    endcase
                end
            end
        end
    endgenerate

    always_ff @(posedge clk) begin : out_proc
        integer m;
        if (!rst && load_out) begin
            for (m = 0; m < N; m = m + 1) begin
                out_data[m*WIDTH +: WIDTH] <= arr[m];
            end
        end
    end

endmodule
