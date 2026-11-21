module hill_cipher (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [14:0] plaintext,
    input  logic [44:0] key,
    output logic [14:0] ciphertext,
    output logic        done
);

    localparam logic [1:0] IDLE = 2'd0;
    localparam logic [1:0] SUM  = 2'd1;
    localparam logic [1:0] MOD  = 2'd2;

    logic [1:0] state;

    logic [4:0] p0, p1, p2;
    logic [4:0] k00, k01, k02;
    logic [4:0] k10, k11, k12;
    logic [4:0] k20, k21, k22;

    logic [9:0]  prod00, prod01, prod02;
    logic [9:0]  prod10, prod11, prod12;
    logic [9:0]  prod20, prod21, prod22;

    logic [11:0] sum0, sum1, sum2;

    assign p0  = plaintext[14:10];
    assign p1  = plaintext[9:5];
    assign p2  = plaintext[4:0];

    assign k00 = key[44:40];
    assign k01 = key[39:35];
    assign k02 = key[34:30];
    assign k10 = key[29:25];
    assign k11 = key[24:20];
    assign k12 = key[19:15];
    assign k20 = key[14:10];
    assign k21 = key[9:5];
    assign k22 = key[4:0];

    function automatic logic [4:0] mod26(input logic [11:0] val);
        logic [11:0] rem;
        begin
            rem = val;
            if (rem >= 12'd3328) rem = rem - 12'd3328;
            if (rem >= 12'd1664) rem = rem - 12'd1664;
            if (rem >= 12'd832)  rem = rem - 12'd832;
            if (rem >= 12'd416)  rem = rem - 12'd416;
            if (rem >= 12'd208)  rem = rem - 12'd208;
            if (rem >= 12'd104)  rem = rem - 12'd104;
            if (rem >= 12'd52)   rem = rem - 12'd52;
            if (rem >= 12'd26)   rem = rem - 12'd26;
            mod26 = rem[4:0];
        end
    endfunction

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state      <= IDLE;
            ciphertext <= 15'd0;
            done       <= 1'b0;
            prod00     <= 10'd0;
            prod01     <= 10'd0;
            prod02     <= 10'd0;
            prod10     <= 10'd0;
            prod11     <= 10'd0;
            prod12     <= 10'd0;
            prod20     <= 10'd0;
            prod21     <= 10'd0;
            prod22     <= 10'd0;
            sum0       <= 12'd0;
            sum1       <= 12'd0;
            sum2       <= 12'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        prod00 <= {5'd0, k00} * {5'd0, p0};
                        prod01 <= {5'd0, k01} * {5'd0, p1};
                        prod02 <= {5'd0, k02} * {5'd0, p2};
                        prod10 <= {5'd0, k10} * {5'd0, p0};
                        prod11 <= {5'd0, k11} * {5'd0, p1};
                        prod12 <= {5'd0, k12} * {5'd0, p2};
                        prod20 <= {5'd0, k20} * {5'd0, p0};
                        prod21 <= {5'd0, k21} * {5'd0, p1};
                        prod22 <= {5'd0, k22} * {5'd0, p2};
                        state  <= SUM;
                    end
                end

                SUM: begin
                    done  <= 1'b0;
                    sum0  <= {2'd0, prod00} + {2'd0, prod01} + {2'd0, prod02};
                    sum1  <= {2'd0, prod10} + {2'd0, prod11} + {2'd0, prod12};
                    sum2  <= {2'd0, prod20} + {2'd0, prod21} + {2'd0, prod22};
                    state <= MOD;
                end

                MOD: begin
                    ciphertext <= {mod26(sum0), mod26(sum1), mod26(sum2)};
                    done       <= 1'b1;
                    state      <= IDLE;
                end

                default: begin
                    done  <= 1'b0;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule

