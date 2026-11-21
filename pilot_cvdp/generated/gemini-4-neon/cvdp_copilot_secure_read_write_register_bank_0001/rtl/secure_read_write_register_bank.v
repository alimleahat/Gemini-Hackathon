module secure_read_write_register_bank #(
    parameter integer p_address_width = 8,
    parameter integer p_data_width    = 8,
    parameter [p_data_width-1:0] p_unlock_code_0 = 8'hAB,
    parameter [p_data_width-1:0] p_unlock_code_1 = 8'hCD
) (
    input  wire [p_address_width-1:0] i_addr,
    input  wire [p_data_width-1:0]    i_data_in,
    input  wire                       i_read_write_enable,
    input  wire                       i_capture_pulse,
    input  wire                       i_rst_n,
    output reg  [p_data_width-1:0]    o_data_out
);

    localparam integer DEPTH = 1 << p_address_width;

    localparam [p_address_width-1:0] ADDR_0 = 1'b0;
    localparam [p_address_width-1:0] ADDR_1 = 1'b1;

    localparam [1:0] STATE_LOCKED   = 2'b00;
    localparam [1:0] STATE_STEP1    = 2'b01;
    localparam [1:0] STATE_UNLOCKED = 2'b10;

    reg [1:0] r_state;
    reg [p_data_width-1:0] r_reg_bank [0:DEPTH-1];

    initial begin : init_reg_bank
        integer idx;
        for (idx = 0; idx < DEPTH; idx = idx + 1) begin
            r_reg_bank[idx] = {p_data_width{1'b0}};
        end
    end

    wire w_is_addr_0;
    wire w_is_addr_1;
    wire w_mem_write_en;

    assign w_is_addr_0 = (i_addr == ADDR_0);
    assign w_is_addr_1 = (i_addr == ADDR_1);

    assign w_mem_write_en = i_rst_n &&
                            (i_read_write_enable == 1'b0) &&
                            (r_state == STATE_UNLOCKED) &&
                            !w_is_addr_0 &&
                            !w_is_addr_1;

    always @(posedge i_capture_pulse) begin
        if (w_mem_write_en) begin
            r_reg_bank[i_addr] <= i_data_in;
        end
    end

    always @(posedge i_capture_pulse or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state    <= STATE_LOCKED;
            o_data_out <= {p_data_width{1'b0}};
        end else begin
            if (i_read_write_enable == 1'b0) begin
                o_data_out <= {p_data_width{1'b0}};
                case (r_state)
                    STATE_LOCKED: begin
                        if (w_is_addr_0 && (i_data_in == p_unlock_code_0)) begin
                            r_state <= STATE_STEP1;
                        end else begin
                            r_state <= STATE_LOCKED;
                        end
                    end

                    STATE_STEP1: begin
                        if (w_is_addr_1 && (i_data_in == p_unlock_code_1)) begin
                            r_state <= STATE_UNLOCKED;
                        end else if (w_is_addr_0 && (i_data_in == p_unlock_code_0)) begin
                            r_state <= STATE_STEP1;
                        end else begin
                            r_state <= STATE_LOCKED;
                        end
                    end

                    STATE_UNLOCKED: begin
                        if ((w_is_addr_0 && (i_data_in != p_unlock_code_0)) ||
                            (w_is_addr_1 && (i_data_in != p_unlock_code_1))) begin
                            r_state <= STATE_LOCKED;
                        end else begin
                            r_state <= STATE_UNLOCKED;
                        end
                    end

                    default: begin
                        r_state <= STATE_LOCKED;
                    end
                endcase
            end else begin
                case (r_state)
                    STATE_UNLOCKED: begin
                        if (w_is_addr_0 || w_is_addr_1) begin
                            o_data_out <= {p_data_width{1'b0}};
                        end else begin
                            o_data_out <= r_reg_bank[i_addr];
                        end
                        r_state <= STATE_UNLOCKED;
                    end

                    default: begin
                        o_data_out <= {p_data_width{1'b0}};
                        r_state    <= STATE_LOCKED;
                    end
                endcase
            end
        end
    end

endmodule
