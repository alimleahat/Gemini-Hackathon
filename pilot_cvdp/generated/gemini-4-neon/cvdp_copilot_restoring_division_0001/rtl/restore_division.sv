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

    localparam COUNT_WIDTH = $clog2(WIDTH + 1);
    localparam IS_POW2     = ((WIDTH & (WIDTH - 1)) == 0);
    localparam [COUNT_WIDTH-1:0] LAST_ITER = WIDTH - 1;
    localparam [COUNT_WIDTH-1:0] DONE_CNT  = WIDTH;

    logic [WIDTH-1:0]       dividend_reg;
    logic [WIDTH-1:0]       divisor_reg;
    logic                   busy;
    logic [COUNT_WIDTH-1:0] count;

    logic [WIDTH:0]   shifted_rem;
    logic [WIDTH:0]   sub_result;
    logic [WIDTH-1:0] next_remainder;
    logic [WIDTH-1:0] next_quotient;

    always_comb begin
        shifted_rem      = {remainder, dividend_reg[WIDTH-1]};
        sub_result       = shifted_rem - {1'b0, divisor_reg};
        next_remainder   = sub_result[WIDTH] ? shifted_rem[WIDTH-1:0] : sub_result[WIDTH-1:0];
        next_quotient    = quotient << 1;
        next_quotient[0] = ~sub_result[WIDTH];
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            dividend_reg <= {WIDTH{1'b0}};
            divisor_reg  <= {WIDTH{1'b0}};
            quotient     <= {WIDTH{1'b0}};
            remainder    <= {WIDTH{1'b0}};
            valid        <= 1'b0;
            busy         <= 1'b0;
            count        <= {COUNT_WIDTH{1'b0}};
        end else if (busy) begin
            if (IS_POW2) begin
                remainder    <= next_remainder;
                quotient     <= next_quotient;
                dividend_reg <= dividend_reg << 1;
                if (count == LAST_ITER) begin
                    busy  <= 1'b0;
                    valid <= 1'b1;
                    count <= {COUNT_WIDTH{1'b0}};
                end else begin
                    count <= count + 1'b1;
                end
            end else begin
                if (count == DONE_CNT) begin
                    busy  <= 1'b0;
                    valid <= 1'b1;
                    count <= {COUNT_WIDTH{1'b0}};
                end else begin
                    remainder    <= next_remainder;
                    quotient     <= next_quotient;
                    dividend_reg <= dividend_reg << 1;
                    count        <= count + 1'b1;
                end
            end
        end else if (start) begin
            dividend_reg <= dividend;
            divisor_reg  <= divisor;
            remainder    <= {WIDTH{1'b0}};
            quotient     <= {WIDTH{1'b0}};
            valid        <= 1'b0;
            busy         <= 1'b1;
            count        <= {COUNT_WIDTH{1'b0}};
        end else begin
            valid <= 1'b0;
        end
    end

endmodule
