module hill_cipher (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [14:0] plaintext,
    input  logic [44:0] key,
    output logic [14:0] ciphertext,
    output logic        done
);

    localparam logic [1:0] S_IDLE  = 2'd0;
    localparam logic [1:0] S_ACCUM = 2'd1;
    localparam logic [1:0] S_MOD   = 2'd2;

    logic [1:0] state;

    // Unpacked plaintext vector elements
    logic [4:0] pt0, pt1, pt2;
    assign pt0 = plaintext[14:10];
    assign pt1 = plaintext[9:5];
    assign pt2 = plaintext[4:0];

    // Unpacked 3x3 key matrix elements
    logic [4:0] k00, k01, k02;
    logic [4:0] k10, k11, k12;
    logic [4:0] k20, k21, k22;
    assign k00 = key[44:40];
    assign k01 = key[39:35];
    assign k02 = key[34:30];
    assign k10 = key[29:25];
    assign k11 = key[24:20];
    assign k12 = key[19:15];
    assign k20 = key[14:10];
    assign k21 = key[9:5];
    assign k22 = key[4:0];

    // Stage 1: Partial products (max 31 * 31 = 961, fits in 10 bits)
    logic [9:0] p00, p01, p02;
    logic [9:0] p10, p11, p12;
    logic [9:0] p20, p21, p22;

    // Stage 2: Row sums (max 3 * 961 = 2883, fits in 12 bits)
    logic [11:0] sum0, sum1, sum2;

    // Combinational modulo-26 reduction for 12-bit unsigned input
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

    logic [4:0] c0, c1, c2;
    assign c0 = mod26(sum0);
    assign c1 = mod26(sum1);
    assign c2 = mod26(sum2);

    // 3-cycle latency FSM and datapath
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state      <= S_IDLE;
            p00        <= 10'd0;
            p01        <= 10'd0;
            p02        <= 10'd0;
            p10        <= 10'd0;
            p11        <= 10'd0;
            p12        <= 10'd0;
            p20        <= 10'd0;
            p21        <= 10'd0;
            p22        <= 10'd0;
            sum0       <= 12'd0;
            sum1       <= 12'd0;
            sum2       <= 12'd0;
            ciphertext <= 15'd0;
            done       <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        p00   <= {5'd0, k00} * {5'd0, pt0};
                        p01   <= {5'd0, k01} * {5'd0, pt1};
                        p02   <= {5'd0, k02} * {5'd0, pt2};
                        p10   <= {5'd0, k10} * {5'd0, pt0};
                        p11   <= {5'd0, k11} * {5'd0, pt1};
                        p12   <= {5'd0, k12} * {5'd0, pt2};
                        p20   <= {5'd0, k20} * {5'd0, pt0};
                        p21   <= {5'd0, k21} * {5'd0, pt1};
                        p22   <= {5'd0, k22} * {5'd0, pt2};
                        state <= S_ACCUM;
                    end
                end

                S_ACCUM: begin
                    sum0  <= {2'd0, p00} + {2'd0, p01} + {2'd0, p02};
                    sum1  <= {2'd0, p10} + {2'd0, p11} + {2'd0, p12};
                    sum2  <= {2'd0, p20} + {2'd0, p21} + {2'd0, p22};
                    done  <= 1'b0;
                    state <= S_MOD;
                end

                S_MOD: begin
                    ciphertext <= {c0, c1, c2};
                    done       <= 1'b1;
                    state      <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                    done  <= 1'b0;
                end
            endcase
        end
    end

endmodule
