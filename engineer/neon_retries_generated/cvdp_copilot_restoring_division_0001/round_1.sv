module restoring_division #(
    parameter WIDTH = 6
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             start,
    input  logic [WIDTH-1:0] dividend,
    input  logic [WIDTH-1:0] divisor,
    output logic [WIDTH-1:0] quotient,
    output logic [WIDTH-1:0] remainder,
    output logic             valid
);

    localparam IS_POW2     = ((WIDTH & (WIDTH - 1)) == 0);
    localparam COUNT_WIDTH = $clog2(WIDTH + 1);

    localparam [COUNT_WIDTH-1:0] CNT_ZERO  = 0;
    localparam [COUNT_WIDTH-1:0] CNT_ONE   = 1;
    localparam [COUNT_WIDTH-1:0] LAST_ITER = WIDTH - 1;
    localparam [COUNT_WIDTH-1:0] DONE_CNT  = WIDTH;
    localparam [WIDTH-1:0]       DATA_ZERO = 0;

    logic                   busy;
    logic [COUNT_WIDTH-1:0] count;
    logic [WIDTH-1:0]       dvd_reg;
    logic [WIDTH-1:0]       div_reg;
    logic [WIDTH-1:0]       rem_reg;
    logic [WIDTH-1:0]       quot_reg;

    logic [WIDTH:0]         shifted_rem;
    logic [WIDTH:0]         sub_res;
    logic [WIDTH-1:0]       next_rem;
    logic [WIDTH-1:0]       next_quot;
    logic [WIDTH-1:0]       next_dvd;
    logic                   q_bit;

    always_comb begin
        shifted_rem = {rem_reg, dvd_reg[WIDTH-1]};
        sub_res     = shifted_rem - {1'b0, div_reg};
        if (sub_res[WIDTH] == 1'b0) begin
            next_rem = sub_res[WIDTH-1:0];
            q_bit    = 1'b1;
        end else begin
            next_rem = shifted_rem[WIDTH-1:0];
            q_bit    = 1'b0;
        end
        next_quot    = quot_reg << 1;
        next_quot[0] = q_bit;
        next_dvd     = dvd_reg << 1;
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            quotient  <= DATA_ZERO;
            remainder <= DATA_ZERO;
            valid     <= 1'b0;
            busy      <= 1'b0;
            count     <= CNT_ZERO;
            dvd_reg   <= DATA_ZERO;
            div_reg   <= DATA_ZERO;
            rem_reg   <= DATA_ZERO;
            quot_reg  <= DATA_ZERO;
        end else begin
            valid <= 1'b0;
            if (busy) begin
                if (IS_POW2) begin
                    rem_reg  <= next_rem;
                    quot_reg <= next_quot;
                    dvd_reg  <= next_dvd;
                    if (count == LAST_ITER) begin
                        quotient  <= next_quot;
                        remainder <= next_rem;
                        valid     <= 1'b1;
                        busy      <= 1'b0;
                        count     <= CNT_ZERO;
                    end else begin
                        count <= count + CNT_ONE;
                    end
                end else begin
                    if (count == DONE_CNT) begin
                        quotient  <= quot_reg;
                        remainder <= rem_reg;
                        valid     <= 1'b1;
                        busy      <= 1'b0;
                        count     <= CNT_ZERO;
                    end else begin
                        rem_reg  <= next_rem;
                        quot_reg <= next_quot;
                        dvd_reg  <= next_dvd;
                        count    <= count + CNT_ONE;
                    end
                end
            end else if (start) begin
                dvd_reg  <= dividend;
                div_reg  <= divisor;
                rem_reg  <= DATA_ZERO;
                quot_reg <= DATA_ZERO;
                count    <= CNT_ZERO;
                busy     <= 1'b1;
            end
        end
    end

endmodule
