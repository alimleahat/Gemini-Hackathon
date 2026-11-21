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

    localparam p_depth = (1 << p_address_width);

    localparam [p_address_width-1:0] ADDR_0 = 0;
    localparam [p_address_width-1:0] ADDR_1 = 1;

    localparam [1:0] STATE_LOCKED   = 2'b00;
    localparam [1:0] STATE_UNLOCK_0 = 2'b01;
    localparam [1:0] STATE_UNLOCKED = 2'b10;

    reg [1:0]              r_state;
    reg [p_data_width-1:0] r_mem [0:p_depth-1];

    initial begin : init_mem
        integer i;
        for (i = 0; i < p_depth; i = i + 1) begin
            r_mem[i] = {p_data_width{1'b0}};
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
                        if ((i_addr == ADDR_0) && (i_data_in == p_unlock_code_0)) begin
                            r_state <= STATE_UNLOCK_0;
                        end else begin
                            r_state <= STATE_LOCKED;
                        end
                    end

                    STATE_UNLOCK_0: begin
                        if ((i_addr == ADDR_1) && (i_data_in == p_unlock_code_1)) begin
                            r_state <= STATE_UNLOCKED;
                        end else if ((i_addr == ADDR_0) && (i_data_in == p_unlock_code_0)) begin
                            r_state <= STATE_UNLOCK_0;
                        end else begin
                            r_state <= STATE_LOCKED;
                        end
                    end

                    STATE_UNLOCKED: begin
                        if ((i_addr == ADDR_0) && (i_data_in != p_unlock_code_0)) begin
                            r_state <= STATE_LOCKED;
                        end else if ((i_addr == ADDR_1) && (i_data_in != p_unlock_code_1)) begin
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
                        r_state <= STATE_UNLOCKED;
                        if ((i_addr == ADDR_0) || (i_addr == ADDR_1)) begin
                            o_data_out <= {p_data_width{1'b0}};
                        end else begin
                            o_data_out <= r_mem[i_addr];
                        end
                    end

                    default: begin
                        r_state    <= STATE_LOCKED;
                        o_data_out <= {p_data_width{1'b0}};
                    end
                endcase
            end
        end
    end

    always @(posedge i_capture_pulse) begin
        if (i_rst_n && (r_state == STATE_UNLOCKED) && (i_read_write_enable == 1'b0)) begin
            if ((i_addr != ADDR_0) && (i_addr != ADDR_1)) begin
                r_mem[i_addr] <= i_data_in;
            end
        end
    end

endmodule
