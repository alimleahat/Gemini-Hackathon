module TopModule (
    input  clk,
    input  reset,
    input  ena,
    output reg pm,
    output reg [7:0] hh,
    output reg [7:0] mm,
    output reg [7:0] ss
);

    wire ss_roll = (ss == 8'h59);
    wire mm_roll = (mm == 8'h59) && ss_roll;

    always @(posedge clk) begin
        if (reset) begin
            ss <= 8'h00;
            mm <= 8'h00;
            hh <= 8'h12;
            pm <= 1'b0;
        end else if (ena) begin
            if (ss == 8'h59) begin
                ss <= 8'h00;
            end else if (ss[3:0] == 4'h9) begin
                ss <= {ss[7:4] + 4'd1, 4'h0};
            end else begin
                ss <= {ss[7:4], ss[3:0] + 4'd1};
            end

            if (ss_roll) begin
                if (mm == 8'h59) begin
                    mm <= 8'h00;
                end else if (mm[3:0] == 4'h9) begin
                    mm <= {mm[7:4] + 4'd1, 4'h0};
                end else begin
                    mm <= {mm[7:4], mm[3:0] + 4'd1};
                end
            end

            if (mm_roll) begin
                if (hh == 8'h12) begin
                    hh <= 8'h01;
                end else if (hh == 8'h09) begin
                    hh <= 8'h10;
                end else begin
                    hh <= hh + 8'h01;
                end

                if (hh == 8'h11) begin
                    pm <= ~pm;
                end
            end
        end
    end

endmodule
