module hill_cipher (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [14:0] plaintext,
    input  logic [44:0] key,
    output logic [14:0] ciphertext,
    output logic        done
);

    localparam logic [1:0] S_IDLE = 2'd0;
    localparam logic [1:0] S_ROW1 = 2'd1;
    localparam logic [1:0] S_ROW2 = 2'd2;
    localparam logic [1:0] S_DONE = 2'd3;

    logic [1:0]  state;
    logic [14:0] p_reg;
    logic [29:0] k_rem_reg;
    logic [4:0]  c0_reg;
    logic [4:0]  c1_reg;

    logic [4:0]  mac_p0, mac_p1, mac_p2;
    logic [4:0]  mac_k0, mac_k1, mac_k2;
    logic [9:0]  prod0, prod1, prod2;
    logic [11:0] row_sum;
    logic [4:0]  row_mod;

    function automatic logic [4:0] mod26 (input logic [11:0] val);
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

    always_comb begin
        case (state)
            S_ROW1: begin
                mac_p0 = p_reg[14:10];
                mac_p1 = p_reg[9:5];
                mac_p2 = p_reg[4:0];
                mac_k0 = k_rem_reg[29:25];
                mac_k1 = k_rem_reg[24:20];
                mac_k2 = k_rem_reg[19:15];
            end
            S_ROW2: begin
                mac_p0 = p_reg[14:10];
                mac_p1 = p_reg[9:5];
                mac_p2 = p_reg[4:0];
                mac_k0 = k_rem_reg[14:10];
                mac_k1 = k_rem_reg[9:5];
                mac_k2 = k_rem_reg[4:0];
            end
            default: begin
                mac_p0 = plaintext[14:10];
                mac_p1 = plaintext[9:5];
                mac_p2 = plaintext[4:0];
                mac_k0 = key[44:40];
                mac_k1 = key[39:35];
                mac_k2 = key[34:30];
            end
        endcase

        prod0   = {5'd0, mac_k0} * {5'd0, mac_p0};
        prod1   = {5'd0, mac_k1} * {5'd0, mac_p1};
        prod2   = {5'd0, mac_k2} * {5'd0, mac_p2};
        row_sum = {2'd0, prod0} + {2'd0, prod1} + {2'd0, prod2};
        row_mod = mod26(row_sum);
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state      <= S_IDLE;
            p_reg      <= 15'd0;
            k_rem_reg  <= 30'd0;
            c0_reg     <= 5'd0;
            c1_reg     <= 5'd0;
            ciphertext <= 15'd0;
            done       <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        p_reg     <= plaintext;
                        k_rem_reg <= key[29:0];
                        c0_reg    <= row_mod;
                        state     <= S_ROW1;
                    end
                end

                S_ROW1: begin
                    done   <= 1'b0;
                    c1_reg <= row_mod;
                    state  <= S_ROW2;
                end

                S_ROW2: begin
                    ciphertext <= {c0_reg, c1_reg, row_mod};
                    done       <= 1'b1;
                    state      <= S_DONE;
                end

                S_DONE: begin
                    done <= 1'b0;
                    if (start) begin
                        p_reg     <= plaintext;
                        k_rem_reg <= key[29:0];
                        c0_reg    <= row_mod;
                        state     <= S_ROW1;
                    end else begin
                        state <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                    done  <= 1'b0;
                end
            endcase
        end
    end

endmodule
