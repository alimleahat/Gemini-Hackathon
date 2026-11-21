module secure_read_write_register_bank #(
    parameter integer p_address_width            = 8,
    parameter integer p_data_width               = 8,
    parameter [p_data_width-1:0] p_unlock_code_0 = 8'hAB,
    parameter [p_data_width-1:0] p_unlock_code_1 = 8'hCD
) (
    input  logic [p_address_width-1:0] i_addr,
    input  logic [p_data_width-1:0]    i_data_in,
    input  logic                       i_read_write_enable,
    input  logic                       i_capture_pulse,
    input  logic                       i_rst_n,
    output logic [p_data_width-1:0]    o_data_out
);

    localparam integer DEPTH = 1 << p_address_width;

    localparam [p_address_width-1:0] ADDR_0 = 0;
    localparam [p_address_width-1:0] ADDR_1 = 1;

    localparam [1:0] STATE_LOCKED       = 2'b00;
    localparam [1:0] STATE_UNLOCK_STEP1 = 2'b01;
    localparam [1:0] STATE_UNLOCKED     = 2'b10;

    logic [1:0] state;
    logic [p_data_width-1:0] reg_bank [0:DEPTH-1];

    initial begin : init_reg_bank
        integer idx;
        for (idx = 0; idx < DEPTH; idx = idx + 1) begin
            reg_bank[idx] = {p_data_width{1'b0}};
        end
    end

    always_ff @(posedge i_capture_pulse or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state      <= STATE_LOCKED;
            o_data_out <= {p_data_width{1'b0}};
        end else begin
            o_data_out <= {p_data_width{1'b0}};

            case (state)
                STATE_LOCKED: begin
                    if (!i_read_write_enable && (i_addr == ADDR_0) && (i_data_in == p_unlock_code_0)) begin
                        state <= STATE_UNLOCK_STEP1;
                    end else begin
                        state <= STATE_LOCKED;
                    end
                end

                STATE_UNLOCK_STEP1: begin
                    if (!i_read_write_enable && (i_addr == ADDR_1) && (i_data_in == p_unlock_code_1)) begin
                        state <= STATE_UNLOCKED;
                    end else if (!i_read_write_enable && (i_addr == ADDR_0) && (i_data_in == p_unlock_code_0)) begin
                        state <= STATE_UNLOCK_STEP1;
                    end else begin
                        state <= STATE_LOCKED;
                    end
                end

                STATE_UNLOCKED: begin
                    if (!i_read_write_enable) begin
                        if (i_addr == ADDR_0) begin
                            if (i_data_in != p_unlock_code_0) begin
                                state <= STATE_LOCKED;
                            end
                        end else if (i_addr == ADDR_1) begin
                            if (i_data_in != p_unlock_code_1) begin
                                state <= STATE_LOCKED;
                            end
                        end
                    end else begin
                        if ((i_addr != ADDR_0) && (i_addr != ADDR_1)) begin
                            o_data_out <= reg_bank[i_addr];
                        end
                    end
                end

                default: begin
                    state <= STATE_LOCKED;
                end
            endcase
        end
    end

    always @(posedge i_capture_pulse) begin
        if (i_rst_n && !i_read_write_enable) begin
            if ((state == STATE_UNLOCKED) || (i_addr == ADDR_0) || (i_addr == ADDR_1)) begin
                reg_bank[i_addr] <= i_data_in;
            end
        end
    end

endmodule

