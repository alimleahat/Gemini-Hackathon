module secure_read_write_register_bank #(
    parameter p_address_width = 8,
    parameter p_data_width    = 8,
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

    localparam [1:0] STATE_LOCKED      = 2'b00;
    localparam [1:0] STATE_WAIT_CODE_1 = 2'b01;
    localparam [1:0] STATE_UNLOCKED    = 2'b10;

    localparam [p_address_width-1:0] ADDR_0 = 0;
    localparam [p_address_width-1:0] ADDR_1 = 1;
    localparam integer MEM_DEPTH = 1 << p_address_width;

    reg [1:0] state;
    reg [p_data_width-1:0] reg_bank [0:MEM_DEPTH-1];

    always @(posedge i_capture_pulse) begin
        if ((state == STATE_UNLOCKED) && !i_read_write_enable && (i_addr != ADDR_0) && (i_addr != ADDR_1)) begin
            reg_bank[i_addr] <= i_data_in;
        end
    end

    always @(posedge i_capture_pulse or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state      <= STATE_LOCKED;
            o_data_out <= {p_data_width{1'b0}};
        end else begin
            case (state)
                STATE_LOCKED: begin
                    o_data_out <= {p_data_width{1'b0}};
                    if (!i_read_write_enable && (i_addr == ADDR_0) && (i_data_in == p_unlock_code_0)) begin
                        state <= STATE_WAIT_CODE_1;
                    end else begin
                        state <= STATE_LOCKED;
                    end
                end

                STATE_WAIT_CODE_1: begin
                    o_data_out <= {p_data_width{1'b0}};
                    if (!i_read_write_enable) begin
                        if ((i_addr == ADDR_1) && (i_data_in == p_unlock_code_1)) begin
                            state <= STATE_UNLOCKED;
                        end else if ((i_addr == ADDR_0) && (i_data_in == p_unlock_code_0)) begin
                            state <= STATE_WAIT_CODE_1;
                        end else begin
                            state <= STATE_LOCKED;
                        end
                    end else begin
                        state <= STATE_LOCKED;
                    end
                end

                STATE_UNLOCKED: begin
                    if (!i_read_write_enable) begin
                        o_data_out <= {p_data_width{1'b0}};
                        if (i_addr == ADDR_0) begin
                            if (i_data_in != p_unlock_code_0) begin
                                state <= STATE_LOCKED;
                            end else begin
                                state <= STATE_UNLOCKED;
                            end
                        end else if (i_addr == ADDR_1) begin
                            if (i_data_in != p_unlock_code_1) begin
                                state <= STATE_LOCKED;
                            end else begin
                                state <= STATE_UNLOCKED;
                            end
                        end else begin
                            state <= STATE_UNLOCKED;
                        end
                    end else begin
                        state <= STATE_UNLOCKED;
                        if ((i_addr == ADDR_0) || (i_addr == ADDR_1)) begin
                            o_data_out <= {p_data_width{1'b0}};
                        end else begin
                            o_data_out <= reg_bank[i_addr];
                        end
                    end
                end

                default: begin
                    state      <= STATE_LOCKED;
                    o_data_out <= {p_data_width{1'b0}};
                end
            endcase
        end
    end

endmodule
