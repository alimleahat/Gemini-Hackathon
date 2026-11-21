module secure_read_write_register_bank #(
    parameter p_address_width = 8,
    parameter p_data_width    = 8,
    parameter p_unlock_code_0 = 8'hAB,
    parameter p_unlock_code_1 = 8'hCD
) (
    input  wire [p_address_width-1:0] i_addr,
    input  wire [p_data_width-1:0]    i_data_in,
    input  wire                       i_read_write_enable,
    input  wire                       i_capture_pulse,
    input  wire                       i_rst_n,
    output reg  [p_data_width-1:0]    o_data_out
);

    localparam [p_address_width-1:0] ADDR_0        = 0;
    localparam [p_address_width-1:0] ADDR_1        = 1;
    localparam [p_data_width-1:0]    UNLOCK_CODE_0 = p_unlock_code_0;
    localparam [p_data_width-1:0]    UNLOCK_CODE_1 = p_unlock_code_1;

    localparam [1:0] S_LOCKED        = 2'b00;
    localparam [1:0] S_UNLOCK_STEP_1 = 2'b01;
    localparam [1:0] S_UNLOCKED      = 2'b10;

    localparam integer MEM_DEPTH = (1 << p_address_width);

    reg [1:0]              r_state;
    reg [p_data_width-1:0] r_reg_bank [0:MEM_DEPTH-1];

    integer idx;
    initial begin
        for (idx = 0; idx < MEM_DEPTH; idx = idx + 1) begin
            r_reg_bank[idx] = {p_data_width{1'b0}};
        end
    end

    wire w_is_write = ~i_read_write_enable;
    wire w_is_addr0 = (i_addr == ADDR_0);
    wire w_is_addr1 = (i_addr == ADDR_1);
    wire w_code0_ok = (i_data_in == UNLOCK_CODE_0);
    wire w_code1_ok = (i_data_in == UNLOCK_CODE_1);

    always @(posedge i_capture_pulse or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state    <= S_LOCKED;
            o_data_out <= {p_data_width{1'b0}};
        end else begin
            case (r_state)
                S_LOCKED: begin
                    o_data_out <= {p_data_width{1'b0}};
                    if (w_is_write && w_is_addr0 && w_code0_ok) begin
                        r_state <= S_UNLOCK_STEP_1;
                    end else begin
                        r_state <= S_LOCKED;
                    end
                end

                S_UNLOCK_STEP_1: begin
                    o_data_out <= {p_data_width{1'b0}};
                    if (w_is_write && w_is_addr1 && w_code1_ok) begin
                        r_state <= S_UNLOCKED;
                    end else if (w_is_write && w_is_addr0 && w_code0_ok) begin
                        r_state <= S_UNLOCK_STEP_1;
                    end else begin
                        r_state <= S_LOCKED;
                    end
                end

                S_UNLOCKED: begin
                    if (w_is_write) begin
                        o_data_out <= {p_data_width{1'b0}};
                        if (w_is_addr0) begin
                            if (!w_code0_ok) begin
                                r_state <= S_LOCKED;
                            end else begin
                                r_state <= S_UNLOCKED;
                            end
                        end else if (w_is_addr1) begin
                            if (!w_code1_ok) begin
                                r_state <= S_LOCKED;
                            end else begin
                                r_state <= S_UNLOCKED;
                            end
                        end else begin
                            r_reg_bank[i_addr] <= i_data_in;
                            r_state            <= S_UNLOCKED;
                        end
                    end else begin
                        r_state <= S_UNLOCKED;
                        if (w_is_addr0 || w_is_addr1) begin
                            o_data_out <= {p_data_width{1'b0}};
                        end else begin
                            o_data_out <= r_reg_bank[i_addr];
                        end
                    end
                end

                default: begin
                    r_state    <= S_LOCKED;
                    o_data_out <= {p_data_width{1'b0}};
                end
            endcase
        end
    end

endmodule
