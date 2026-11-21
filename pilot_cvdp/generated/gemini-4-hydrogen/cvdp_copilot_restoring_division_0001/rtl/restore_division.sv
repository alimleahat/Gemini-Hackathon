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

    localparam IS_POW2   = ((WIDTH & (WIDTH - 1)) == 0);
    localparam CNT_WIDTH = $clog2(WIDTH + 1);
    localparam [CNT_WIDTH-1:0] CNT_ONE  = 1;
    localparam [CNT_WIDTH-1:0] CNT_LAST = WIDTH - 1;

    logic                 busy;
    logic [CNT_WIDTH-1:0] count;
    logic [WIDTH-1:0]     div_reg;
    logic [WIDTH-1:0]     divisor_reg;
    logic [WIDTH-1:0]     rem_reg;
    logic [WIDTH-1:0]     quot_reg;

    logic                 use_init_step;
    logic [WIDTH-1:0]     step_rem_in;
    logic                 step_div_bit;
    logic [WIDTH-1:0]     step_divisor;
    logic [WIDTH-1:0]     step_quot_in;

    logic [WIDTH:0]       rem_shifted;
    logic [WIDTH:0]       sub_res;
    logic                 sub_neg;
    logic [WIDTH-1:0]     next_rem;
    logic [WIDTH:0]       next_quot_ext;
    logic [WIDTH-1:0]     next_quot;

    assign use_init_step = (!busy && start && IS_POW2);
    assign step_rem_in   = use_init_step ? {WIDTH{1'b0}}     : rem_reg;
    assign step_div_bit  = use_init_step ? dividend[WIDTH-1] : div_reg[WIDTH-1];
    assign step_divisor  = use_init_step ? divisor           : divisor_reg;
    assign step_quot_in  = use_init_step ? {WIDTH{1'b0}}     : quot_reg;

    assign rem_shifted   = {step_rem_in, step_div_bit};
    assign sub_res       = rem_shifted - {1'b0, step_divisor};
    assign sub_neg       = sub_res[WIDTH];
    assign next_rem      = sub_neg ? rem_shifted[WIDTH-1:0] : sub_res[WIDTH-1:0];
    assign next_quot_ext = {step_quot_in, ~sub_neg};
    assign next_quot     = next_quot_ext[WIDTH-1:0];

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            busy        <= 1'b0;
            valid       <= 1'b0;
            quotient    <= {WIDTH{1'b0}};
            remainder   <= {WIDTH{1'b0}};
            div_reg     <= {WIDTH{1'b0}};
            divisor_reg <= {WIDTH{1'b0}};
            rem_reg     <= {WIDTH{1'b0}};
            quot_reg    <= {WIDTH{1'b0}};
            count       <= {CNT_WIDTH{1'b0}};
        end else begin
            valid <= 1'b0;

            if (!busy) begin
                if (start) begin
                    if (IS_POW2) begin
                        if (WIDTH == 1) begin
                            quotient  <= next_quot;
                            remainder <= next_rem;
                            valid     <= 1'b1;
                        end else begin
                            div_reg     <= dividend << 1;
                            divisor_reg <= divisor;
                            rem_reg     <= next_rem;
                            quot_reg    <= next_quot;
                            count       <= CNT_ONE;
                            busy        <= 1'b1;
                        end
                    end else begin
                        div_reg     <= dividend;
                        divisor_reg <= divisor;
                        rem_reg     <= {WIDTH{1'b0}};
                        quot_reg    <= {WIDTH{1'b0}};
                        count       <= {CNT_WIDTH{1'b0}};
                        busy        <= 1'b1;
                    end
                end
            end else begin
                div_reg  <= div_reg << 1;
                rem_reg  <= next_rem;
                quot_reg <= next_quot;
                if (count == CNT_LAST) begin
                    quotient  <= next_quot;
                    remainder <= next_rem;
                    valid     <= 1'b1;
                    busy      <= 1'b0;
                end else begin
                    count <= count + CNT_ONE;
                end
            end
        end
    end

endmodule
