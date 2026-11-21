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

    localparam int CNT_W = (N > 1) ? $clog2(N) : 1;
    localparam logic [CNT_W-1:0] MAX_I   = N - 1;
    localparam logic [CNT_W-1:0] MAX_J   = (N > 1) ? (N - 2) : 0;
    localparam logic [CNT_W-1:0] CNT_ONE = 1;

    state_t state;
    logic [WIDTH-1:0] arr [0:N-1];
    logic [CNT_W-1:0] i;
    logic [CNT_W-1:0] j;

    integer k_fsm;
    integer k_out;

    generate
        if (N > 1) begin : gen_multi
            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    state <= IDLE;
                    done  <= 1'b0;
                    i     <= {CNT_W{1'b0}};
                    j     <= {CNT_W{1'b0}};
                    for (k_fsm = 0; k_fsm < N; k_fsm = k_fsm + 1) begin
                        arr[k_fsm] <= {WIDTH{1'b0}};
                    end
                end else begin
                    case (state)
                        IDLE: begin
                            done <= 1'b0;
                            if (start) begin
                                for (k_fsm = 0; k_fsm < N; k_fsm = k_fsm + 1) begin
                                    arr[k_fsm] <= in_data[k_fsm*WIDTH +: WIDTH];
                                end
                                i     <= {CNT_W{1'b0}};
                                j     <= {CNT_W{1'b0}};
                                state <= SORTING;
                            end
                        end

                        SORTING: begin
                            done <= 1'b0;
                            if (arr[j] > arr[j + CNT_ONE]) begin
                                arr[j]           <= arr[j + CNT_ONE];
                                arr[j + CNT_ONE] <= arr[j];
                            end

                            if (j == MAX_J) begin
                                j <= {CNT_W{1'b0}};
                                if (i == MAX_I) begin
                                    state <= DONE;
                                end else begin
                                    i <= i + CNT_ONE;
                                end
                            end else begin
                                j <= j + CNT_ONE;
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
        end else begin : gen_single
            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    state  <= IDLE;
                    done   <= 1'b0;
                    i      <= {CNT_W{1'b0}};
                    j      <= {CNT_W{1'b0}};
                    arr[0] <= {WIDTH{1'b0}};
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
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst && (state == DONE)) begin
            for (k_out = 0; k_out < N; k_out = k_out + 1) begin
                out_data[k_out*WIDTH +: WIDTH] <= arr[k_out];
            end
        end
    end

endmodule

