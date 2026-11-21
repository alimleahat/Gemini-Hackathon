module vga_controller #(
    parameter H_ACTIVE = 640,
    parameter H_FRONT  = 16,
    parameter H_PULSE  = 96,
    parameter H_BACK   = 48,
    parameter V_ACTIVE = 480,
    parameter V_FRONT  = 10,
    parameter V_PULSE  = 2,
    parameter V_BACK   = 33
) (
    input  logic       clock,
    input  logic       reset,
    input  logic [7:0] color_in,
    output logic       hsync,
    output logic       vsync,
    output logic [7:0] red,
    output logic [7:0] green,
    output logic [7:0] blue,
    output logic [9:0] next_x,
    output logic [9:0] next_y,
    output logic       sync,
    output logic       clk,
    output logic       blank
);

    localparam [1:0] H_ACTIVE_STATE = 2'd0,
                     H_FRONT_STATE  = 2'd1,
                     H_PULSE_STATE  = 2'd2,
                     H_BACK_STATE   = 2'd3;

    localparam [1:0] V_ACTIVE_STATE = 2'd0,
                     V_FRONT_STATE  = 2'd1,
                     V_PULSE_STATE  = 2'd2,
                     V_BACK_STATE   = 2'd3;

    localparam [9:0] H_ACTIVE_END = H_ACTIVE - 1;
    localparam [9:0] H_FRONT_END  = H_FRONT  - 1;
    localparam [9:0] H_PULSE_END  = H_PULSE  - 1;
    localparam [9:0] H_BACK_LINE  = H_BACK   - 2;
    localparam [9:0] H_BACK_END   = H_BACK   - 1;

    localparam [9:0] V_ACTIVE_END = V_ACTIVE - 1;
    localparam [9:0] V_FRONT_END  = V_FRONT  - 1;
    localparam [9:0] V_PULSE_END  = V_PULSE  - 1;
    localparam [9:0] V_BACK_END   = V_BACK   - 1;

    logic [9:0] h_counter;
    logic [9:0] v_counter;
    logic [1:0] h_state;
    logic [1:0] v_state;
    logic       line_done;

    assign clk   = clock;
    assign sync  = 1'b0;
    assign blank = hsync & vsync;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            h_counter <= 10'd0;
            v_counter <= 10'd0;
            h_state   <= H_ACTIVE_STATE;
            v_state   <= V_ACTIVE_STATE;
            line_done <= 1'b0;
            hsync     <= 1'b1;
            vsync     <= 1'b1;
            red       <= 8'd0;
            green     <= 8'd0;
            blue      <= 8'd0;
            next_x    <= 10'd0;
            next_y    <= 10'd0;
        end else begin
            case (h_state)
                H_ACTIVE_STATE: begin
                    hsync     <= 1'b1;
                    line_done <= 1'b0;
                    if (h_counter == H_ACTIVE_END) begin
                        h_counter <= 10'd0;
                        h_state   <= H_FRONT_STATE;
                    end else begin
                        h_counter <= h_counter + 10'd1;
                    end
                end

                H_FRONT_STATE: begin
                    hsync     <= 1'b1;
                    line_done <= 1'b0;
                    if (h_counter == H_FRONT_END) begin
                        h_counter <= 10'd0;
                        h_state   <= H_PULSE_STATE;
                    end else begin
                        h_counter <= h_counter + 10'd1;
                    end
                end

                H_PULSE_STATE: begin
                    hsync     <= 1'b0;
                    line_done <= 1'b0;
                    if (h_counter == H_PULSE_END) begin
                        h_counter <= 10'd0;
                        h_state   <= H_BACK_STATE;
                    end else begin
                        h_counter <= h_counter + 10'd1;
                    end
                end

                H_BACK_STATE: begin
                    hsync <= 1'b1;
                    if (h_counter == H_BACK_LINE) begin
                        line_done <= 1'b1;
                        h_counter <= h_counter + 10'd1;
                    end else if (h_counter == H_BACK_END) begin
                        line_done <= 1'b0;
                        h_counter <= 10'd0;
                        h_state   <= H_ACTIVE_STATE;
                    end else begin
                        line_done <= 1'b0;
                        h_counter <= h_counter + 10'd1;
                    end
                end

                default: begin
                    hsync     <= 1'b1;
                    line_done <= 1'b0;
                    h_counter <= 10'd0;
                    h_state   <= H_ACTIVE_STATE;
                end
            endcase

            case (v_state)
                V_ACTIVE_STATE: begin
                    vsync <= 1'b1;
                    if (line_done) begin
                        if (v_counter == V_ACTIVE_END) begin
                            v_counter <= 10'd0;
                            v_state   <= V_FRONT_STATE;
                        end else begin
                            v_counter <= v_counter + 10'd1;
                        end
                    end
                end

                V_FRONT_STATE: begin
                    vsync <= 1'b1;
                    if (line_done) begin
                        if (v_counter == V_FRONT_END) begin
                            v_counter <= 10'd0;
                            v_state   <= V_PULSE_STATE;
                        end else begin
                            v_counter <= v_counter + 10'd1;
                        end
                    end
                end

                V_PULSE_STATE: begin
                    vsync <= 1'b0;
                    if (line_done) begin
                        if (v_counter == V_PULSE_END) begin
                            v_counter <= 10'd0;
                            v_state   <= V_BACK_STATE;
                        end else begin
                            v_counter <= v_counter + 10'd1;
                        end
                    end
                end

                V_BACK_STATE: begin
                    vsync <= 1'b1;
                    if (line_done) begin
                        if (v_counter == V_BACK_END) begin
                            v_counter <= 10'd0;
                            v_state   <= V_ACTIVE_STATE;
                        end else begin
                            v_counter <= v_counter + 10'd1;
                        end
                    end
                end

                default: begin
                    vsync     <= 1'b1;
                    v_counter <= 10'd0;
                    v_state   <= V_ACTIVE_STATE;
                end
            endcase

            if ((h_state == H_ACTIVE_STATE) && (v_state == V_ACTIVE_STATE)) begin
                red    <= {color_in[7:5], 5'd0};
                green  <= {color_in[4:2], 5'd0};
                blue   <= {color_in[1:0], 6'd0};
                next_x <= h_counter;
                next_y <= v_counter;
            end else begin
                red    <= 8'd0;
                green  <= 8'd0;
                blue   <= 8'd0;
                next_x <= 10'd0;
                next_y <= 10'd0;
            end
        end
    end

endmodule
