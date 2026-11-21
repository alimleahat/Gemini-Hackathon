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

    localparam bit IS_POW2       = (WIDTH > 0) && ((WIDTH & (WIDTH - 1)) == 0);
    localparam int ACTIVE_CYCLES = IS_POW2 ? WIDTH : (WIDTH + 1);
    localparam int CNT_WIDTH     = $clog2(ACTIVE_CYCLES + 1);
    localparam logic [CNT_WIDTH-1:0] ACTIVE_CNT = CNT_WIDTH'(ACTIVE_CYCLES);

    logic [WIDTH-1:0] dvs_reg;
    logic             is_idle;
    logic             ce_regs;

    logic [WIDTH:0]   rem_ext;
    logic [WIDTH-1:0] shifted_rem;
    logic [WIDTH:0]   sub_result;
    logic [WIDTH:0]   quot_ext;
    logic [WIDTH-1:0] next_rem;
    logic [WIDTH-1:0] next_quot;

    always_comb begin
        rem_ext     = {remainder, quotient[WIDTH-1]};
        shifted_rem = rem_ext[WIDTH-1:0];
        sub_result  = {1'b0, shifted_rem} - {1'b0, dvs_reg};
        quot_ext    = {quotient, ~sub_result[WIDTH]};
        next_rem    = sub_result[WIDTH] ? shifted_rem : sub_result[WIDTH-1:0];
        next_quot   = quot_ext[WIDTH-1:0];
    end

    generate
        if (WIDTH == 6) begin : gen_w6
            logic [2:0] count;
            logic       next_bit;

            assign is_idle  = (count == 3'b000);
            assign ce_regs  = count[1] | count[0] | (~count[2] & start);
            assign next_bit = (~count[2] & count[1])
                            | (count[2] & ~count[1] & count[0])
                            | (~count[2] & ~count[1] & ~count[0] & start);

            always_ff @(posedge clk or negedge rst) begin
                if (!rst) begin
                    count <= 3'b000;
                    valid <= 1'b0;
                end else begin
                    count <= {count[1:0], next_bit};
                    valid <= (count == 3'b100);
                end
            end
        end else if (WIDTH == 4) begin : gen_w4
            logic [2:0] count;
            logic       next_bit;

            assign is_idle  = (count[1:0] == 2'b00);
            assign ce_regs  = count[1] | count[0] | start;
            assign valid    = count[2] & ~count[1] & ~count[0];
            assign next_bit = (~count[1] & ~count[0] & start)
                            | (~count[2] & count[0]);

            always_ff @(posedge clk or negedge rst) begin
                if (!rst) begin
                    count <= 3'b000;
                end else begin
                    count <= {count[1:0], next_bit};
                end
            end
        end else begin : gen_generic
            logic [CNT_WIDTH-1:0] count;

            assign is_idle = (count == {CNT_WIDTH{1'b0}});
            assign ce_regs = is_idle ? start : (IS_POW2 ? 1'b1 : (count != ACTIVE_CNT));

            always_ff @(posedge clk or negedge rst) begin
                if (!rst) begin
                    count <= {CNT_WIDTH{1'b0}};
                    valid <= 1'b0;
                end else begin
                    valid <= (count == ACTIVE_CNT);
                    if (is_idle) begin
                        if (start) begin
                            count <= {{(CNT_WIDTH-1){1'b0}}, 1'b1};
                        end
                    end else if (count == ACTIVE_CNT) begin
                        count <= {CNT_WIDTH{1'b0}};
                    end else begin
                        count <= count + 1'b1;
                    end
                end
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            quotient  <= {WIDTH{1'b0}};
            remainder <= {WIDTH{1'b0}};
            dvs_reg   <= {WIDTH{1'b0}};
        end else begin
            if (is_idle) begin
                dvs_reg <= divisor;
            end
            if (ce_regs) begin
                quotient  <= is_idle ? dividend : next_quot;
                remainder <= is_idle ? {WIDTH{1'b0}} : next_rem;
            end
        end
    end

endmodule
