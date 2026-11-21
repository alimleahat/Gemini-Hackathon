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

    localparam CNT_WIDTH = $clog2(WIDTH + 1);
    localparam IS_POW2   = (WIDTH > 0) && ((WIDTH & (WIDTH - 1)) == 0);
    localparam [CNT_WIDTH-1:0] LAST_ITER = WIDTH - 1;
    localparam [CNT_WIDTH-1:0] DONE_CNT  = WIDTH;

    logic [WIDTH-1:0]     rem_reg;
    logic [WIDTH-1:0]     quot_reg;
    logic [WIDTH-1:0]     div_reg;
    logic [WIDTH-1:0]     dvs_reg;
    logic [CNT_WIDTH-1:0] count;
    logic                 busy;

    logic [WIDTH:0]   shifted_rem;
    logic [WIDTH+1:0] sub_result;
    logic [WIDTH-1:0] next_rem;
    logic [WIDTH-1:0] next_quot;

    always_comb begin
        shifted_rem = {rem_reg, div_reg[WIDTH-1]};
        sub_result  = {1'b0, shifted_rem} - {2'b00, dvs_reg};
        next_quot   = quot_reg << 1;
        if (sub_result[WIDTH+1] == 1'b0) begin
            next_rem     = sub_result[WIDTH-1:0];
            next_quot[0] = 1'b1;
        end else begin
            next_rem     = shifted_rem[WIDTH-1:0];
            next_quot[0] = 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            quotient  <= {WIDTH{1'b0}};
            remainder <= {WIDTH{1'b0}};
            valid     <= 1'b0;
            rem_reg   <= {WIDTH{1'b0}};
            quot_reg  <= {WIDTH{1'b0}};
            div_reg   <= {WIDTH{1'b0}};
            dvs_reg   <= {WIDTH{1'b0}};
            count     <= {CNT_WIDTH{1'b0}};
            busy      <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (!busy) begin
                if (start) begin
                    div_reg  <= dividend;
                    dvs_reg  <= divisor;
                    rem_reg  <= {WIDTH{1'b0}};
                    quot_reg <= {WIDTH{1'b0}};
                    count    <= {CNT_WIDTH{1'b0}};
                    busy     <= 1'b1;
                end
            end else begin
                if (IS_POW2) begin
                    rem_reg  <= next_rem;
                    quot_reg <= next_quot;
                    div_reg  <= div_reg << 1;
                    if (count == LAST_ITER) begin
                        quotient  <= next_quot;
                        remainder <= next_rem;
                        valid     <= 1'b1;
                        busy      <= 1'b0;
                        count     <= {CNT_WIDTH{1'b0}};
                    end else begin
                        count <= count + 1'b1;
                    end
                end else begin
                    if (count == DONE_CNT) begin
                        quotient  <= quot_reg;
                        remainder <= rem_reg;
                        valid     <= 1'b1;
                        busy      <= 1'b0;
                        count     <= {CNT_WIDTH{1'b0}};
                    end else begin
                        rem_reg  <= next_rem;
                        quot_reg <= next_quot;
                        div_reg  <= div_reg << 1;
                        count    <= count + 1'b1;
                    end
                end
            end
        end
    end

endmodule
