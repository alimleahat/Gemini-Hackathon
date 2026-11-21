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

    localparam CNT_W   = (WIDTH > 1) ? $clog2(WIDTH) : 1;
    localparam IS_POW2 = ((WIDTH & (WIDTH - 1)) == 0);

    logic [WIDTH-1:0] dividend_reg;
    logic [WIDTH-1:0] divisor_reg;
    logic [CNT_W-1:0] count;
    logic             busy;

    logic [WIDTH:0]   shifted_rem;
    logic [WIDTH:0]   sub_result;
    logic [WIDTH-1:0] next_rem;
    logic [WIDTH-1:0] next_quot;

    always_comb begin
        shifted_rem = {remainder, dividend_reg[WIDTH-1]};
        sub_result  = shifted_rem - {1'b0, divisor_reg};
        next_quot   = quotient << 1;
        if (sub_result[WIDTH] == 1'b0) begin
            next_rem     = sub_result[WIDTH-1:0];
            next_quot[0] = 1'b1;
        end else begin
            next_rem     = shifted_rem[WIDTH-1:0];
        end
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            dividend_reg <= '0;
            divisor_reg  <= '0;
            quotient     <= '0;
            remainder    <= '0;
            count        <= '0;
            busy         <= 1'b0;
            valid        <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (!busy) begin
                if (start) begin
                    dividend_reg <= dividend;
                    divisor_reg  <= divisor;
                    quotient     <= '0;
                    remainder    <= '0;
                    count        <= '0;
                    busy         <= 1'b1;
                end
            end else begin
                if (IS_POW2) begin
                    remainder    <= next_rem;
                    quotient     <= next_quot;
                    dividend_reg <= dividend_reg << 1;
                    if (count == WIDTH - 1) begin
                        valid <= 1'b1;
                        busy  <= 1'b0;
                        count <= '0;
                    end else begin
                        count <= count + 1'b1;
                    end
                end else begin
                    if (count < WIDTH) begin
                        remainder    <= next_rem;
                        quotient     <= next_quot;
                        dividend_reg <= dividend_reg << 1;
                        count        <= count + 1'b1;
                    end else begin
                        valid <= 1'b1;
                        busy  <= 1'b0;
                        count <= '0;
                    end
                end
            end
        end
    end

endmodule
