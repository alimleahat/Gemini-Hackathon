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

    generate
        if (N == 1) begin : gen_n1
            logic [1:0]       cnt;
            logic             is_idle;
            logic             load;
            logic             is_done_state;
            logic [WIDTH-1:0] arr0;

            assign is_done_state = ~cnt[1] & ~cnt[0];
            assign done          = cnt[0];
            assign is_idle       = cnt[1] | cnt[0];
            assign load          = is_idle & start;

            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    cnt  <= 2'd2;
                    arr0 <= {WIDTH{1'b0}};
                end else if (load) begin
                    cnt  <= 2'd0;
                    arr0 <= in_data;
                end else if (!cnt[1]) begin
                    cnt  <= cnt + 2'd1;
                end
            end

            always_ff @(posedge clk) begin
                if (!rst && is_done_state) begin
                    out_data <= arr0;
                end
            end
        end else if (N == 2) begin : gen_n2
            logic [2:0]       cnt;
            logic             is_idle;
            logic             load;
            logic             is_done_state;
            logic [WIDTH-1:0] arr0;
            logic [WIDTH-1:0] arr1;
            logic             gt_chain;
            logic             do_swap;
            integer           b;

            assign is_done_state = cnt[1] & ~cnt[0];
            assign done          = cnt[1] & cnt[0];
            assign is_idle       = cnt[2] | (cnt[1] & cnt[0]);
            assign load          = is_idle & start;

            always_comb begin
                gt_chain = 1'b0;
                for (b = 0; b < WIDTH; b = b + 1) begin
                    gt_chain = (arr0[b] & ~arr1[b]) | (~(arr0[b] ^ arr1[b]) & gt_chain);
                end
            end

            assign do_swap = ~cnt[0] & gt_chain;

            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    cnt  <= 3'd4;
                    arr0 <= {WIDTH{1'b0}};
                    arr1 <= {WIDTH{1'b0}};
                end else if (load) begin
                    cnt  <= 3'd0;
                    arr0 <= in_data[0 +: WIDTH];
                    arr1 <= in_data[WIDTH +: WIDTH];
                end else begin
                    if (!cnt[2]) begin
                        cnt <= cnt + 3'd1;
                    end
                    if (!do_swap) begin
                        arr0 <= arr1;
                        arr1 <= arr0;
                    end
                end
            end

            always_ff @(posedge clk) begin
                if (!rst && is_done_state) begin
                    out_data[0 +: WIDTH]     <= arr0;
                    out_data[WIDTH +: WIDTH] <= arr1;
                end
            end
        end else if ((N & (N - 1)) == 0) begin : gen_pow2
            localparam int CNT_W = $clog2(N);
            localparam logic [CNT_W-1:0] MAX_VAL = {CNT_W{1'b1}};
            localparam logic [CNT_W-1:0] CNT_TWO = 2;

            logic [CNT_W-1:0] s;
            logic [CNT_W-1:0] p;
            logic [CNT_W-1:0] s_next;
            logic [CNT_W-1:0] p_next;
            logic             s_carry;
            logic             p_carry;
            logic             s_is_last;
            logic             p_max;
            logic             load;
            logic             cnt_ce;
            logic             is_done_state;
            logic             gt_chain;
            logic             do_swap;

            logic [WIDTH-1:0] arr [0:N-1];
            logic [WIDTH-1:0] a0;
            logic [WIDTH-1:0] a1;

            integer b;
            integer k;

            assign a0            = arr[0];
            assign a1            = arr[1];
            assign p_max         = &p;
            assign is_done_state = p_max & ~s[1] & ~s[0];
            assign done          = p_max & s[0];
            assign load          = p_max & (s[1] | s[0]) & start;
            assign cnt_ce        = ~(p_max & s[1] & ~start);

            always_comb begin
                s_carry = 1'b1;
                for (b = 0; b < CNT_W; b = b + 1) begin
                    s_next[b] = ~load & (s[b] ^ s_carry);
                    s_carry   = s_carry & s[b];
                end
                s_is_last = s_carry;
                p_carry   = s_is_last;
                for (b = 0; b < CNT_W; b = b + 1) begin
                    p_next[b] = ~load & (p[b] ^ p_carry);
                    if (b < CNT_W - 1) begin
                        p_carry = p_carry & p[b];
                    end
                end
            end

            always_comb begin
                gt_chain = 1'b0;
                for (b = 0; b < WIDTH; b = b + 1) begin
                    gt_chain = (a0[b] & ~a1[b]) | (~(a0[b] ^ a1[b]) & gt_chain);
                end
            end

            assign do_swap = ~s_is_last & gt_chain;

            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    p <= MAX_VAL;
                    s <= CNT_TWO;
                end else if (cnt_ce) begin
                    p <= p_next;
                    s <= s_next;
                end
            end

            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    for (k = 0; k < N; k = k + 1) begin
                        arr[k] <= {WIDTH{1'b0}};
                    end
                end else begin
                    arr[0] <= load ? in_data[0 +: WIDTH] : (do_swap ? arr[0] : arr[1]);
                    for (k = 1; k < N - 1; k = k + 1) begin
                        arr[k] <= load ? in_data[k*WIDTH +: WIDTH] : arr[k + 1];
                    end
                    arr[N-1] <= load ? in_data[(N-1)*WIDTH +: WIDTH] : (do_swap ? arr[1] : arr[0]);
                end
            end

            always_ff @(posedge clk) begin
                if (!rst && is_done_state) begin
                    for (k = 0; k < N; k = k + 1) begin
                        out_data[k*WIDTH +: WIDTH] <= arr[k];
                    end
                end
            end
        end else begin : gen_gen
            localparam int CNT_W = $clog2(N);
            localparam logic [CNT_W-1:0] MAX_VAL = N - 1;
            localparam logic [CNT_W-1:0] CNT_ONE = 1;
            localparam logic [CNT_W-1:0] CNT_TWO = 2;

            logic [CNT_W-1:0] s;
            logic [CNT_W-1:0] p;
            logic             s_is_last;
            logic             p_max;
            logic             load;
            logic             is_done_state;
            logic             gt_chain;
            logic             do_swap;

            logic [WIDTH-1:0] arr [0:N-1];
            logic [WIDTH-1:0] a0;
            logic [WIDTH-1:0] a1;

            integer b;
            integer k;

            assign a0            = arr[0];
            assign a1            = arr[1];
            assign p_max         = (p == MAX_VAL);
            assign s_is_last     = (s == MAX_VAL);
            assign is_done_state = p_max & ~s[1] & ~s[0];
            assign done          = p_max & s[0];
            assign load          = p_max & (s[1] | s[0]) & start;

            always_comb begin
                gt_chain = 1'b0;
                for (b = 0; b < WIDTH; b = b + 1) begin
                    gt_chain = (a0[b] & ~a1[b]) | (~(a0[b] ^ a1[b]) & gt_chain);
                end
            end

            assign do_swap = ~s_is_last & gt_chain;

            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    p <= MAX_VAL;
                    s <= CNT_TWO;
                end else if (load) begin
                    p <= {CNT_W{1'b0}};
                    s <= {CNT_W{1'b0}};
                end else if (!p_max) begin
                    if (s_is_last) begin
                        s <= {CNT_W{1'b0}};
                        p <= p + CNT_ONE;
                    end else begin
                        s <= s + CNT_ONE;
                    end
                end else if (!s[1]) begin
                    s <= s + CNT_ONE;
                end
            end

            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    for (k = 0; k < N; k = k + 1) begin
                        arr[k] <= {WIDTH{1'b0}};
                    end
                end else begin
                    arr[0] <= load ? in_data[0 +: WIDTH] : (do_swap ? arr[0] : arr[1]);
                    for (k = 1; k < N - 1; k = k + 1) begin
                        arr[k] <= load ? in_data[k*WIDTH +: WIDTH] : arr[k + 1];
                    end
                    arr[N-1] <= load ? in_data[(N-1)*WIDTH +: WIDTH] : (do_swap ? arr[1] : arr[0]);
                end
            end

            always_ff @(posedge clk) begin
                if (!rst && is_done_state) begin
                    for (k = 0; k < N; k = k + 1) begin
                        out_data[k*WIDTH +: WIDTH] <= arr[k];
                    end
                end
            end
        end
    endgenerate

endmodule
