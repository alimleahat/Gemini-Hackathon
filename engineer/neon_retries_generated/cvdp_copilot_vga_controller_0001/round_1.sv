module vga_controller #(
    parameter [9:0] H_ACTIVE = 10'd640,
    parameter [9:0] H_FRONT  = 10'd16,
    parameter [9:0] H_PULSE  = 10'd96,
    parameter [9:0] H_BACK   = 10'd48,
    parameter [9:0] V_ACTIVE = 10'd480,
    parameter [9:0] V_FRONT  = 10'd10,
    parameter [9:0] V_PULSE  = 10'd2,
    parameter [9:0] V_BACK   = 10'd33
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

    localparam logic LOW  = 1'b0;
    localparam logic HIGH = 1'b1;

    localparam [1:0] H_ACTIVE_STATE = 2'd0;
    localparam [1:0] H_FRONT_STATE  = 2'd1;
    localparam [1:0] H_PULSE_STATE  = 2'd2;
    localparam [1:0] H_BACK_STATE   = 2'd3;

    localparam [1:0] V_ACTIVE_STATE = 2'd0;
    localparam [1:0] V_FRONT_STATE  = 2'd1;
    localparam [1:0] V_PULSE_STATE  = 2'd2;
    localparam [1:0] V_BACK_STATE   = 2'd3;

    logic       hsync_reg;
    logic       vsync_reg;
    logic [7:0] red_reg;
    logic [7:0] green_reg;
    logic [7:0] blue_reg;
    logic       line_done;

    logic [9:0] h_counter;
    logic [9:0] v_counter;
    logic [1:0] h_state;
    logic [1:0] v_state;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            h_counter <= 10'd0;
            v_counter <= 10'd0;
            h_state   <= H_ACTIVE_STATE;
            v_state   <= V_ACTIVE_STATE;
            line_done <= LOW;
            hsync_reg <= HIGH;
            vsync_reg <= HIGH;
            red_reg   <= 8'd0;
            green_reg <= 8'd0;
            blue_reg  <= 8'd0;
        end else begin
            case (h_state)
                H_ACTIVE_STATE: begin
                    h_counter <= (h_counter == (H_ACTIVE - 10'd1)) ? 10'd0 : (h_counter + 10'd1);
                    hsync_reg <= HIGH;
                    line_done <= LOW;
                    h_state   <= (h_counter == (H_ACTIVE - 10'd1)) ? H_FRONT_STATE : H_ACTIVE_STATE;
                end
                H_FRONT_STATE: begin
                    h_counter <= (h_counter == (H_FRONT - 10'd1)) ? 10'd0 : (h_counter + 10'd1);
                    hsync_reg <= HIGH;
                    line_done <= LOW;
                    h_state   <= (h_counter == (H_FRONT - 10'd1)) ? H_PULSE_STATE : H_FRONT_STATE;
                end
                H_PULSE_STATE: begin
                    h_counter <= (h_counter == (H_PULSE - 10'd1)) ? 10'd0 : (h_counter + 10'd1);
                    hsync_reg <= LOW;
                    line_done <= LOW;
                    h_state   <= (h_counter == (H_PULSE - 10'd1)) ? H_BACK_STATE : H_PULSE_STATE;
                end
                H_BACK_STATE: begin
                    h_counter <= (h_counter == (H_BACK - 10'd1)) ? 10'd0 : (h_counter + 10'd1);
                    hsync_reg <= HIGH;
                    h_state   <= (h_counter == (H_BACK - 10'd1)) ? H_ACTIVE_STATE : H_BACK_STATE;
                    line_done <= (h_counter == (H_BACK - 10'd2)) ? HIGH : LOW;
                end
                default: begin
                    h_counter <= 10'd0;
                    hsync_reg <= HIGH;
                    line_done <= LOW;
                    h_state   <= H_ACTIVE_STATE;
                end
            endcase

            case (v_state)
                V_ACTIVE_STATE: begin
                    v_counter <= (line_done == HIGH) ? ((v_counter == (V_ACTIVE - 10'd1)) ? 10'd0 : (v_counter + 10'd1)) : v_counter;
                    vsync_reg <= HIGH;
                    v_state   <= (line_done == HIGH) ? ((v_counter == (V_ACTIVE - 10'd1)) ? V_FRONT_STATE : V_ACTIVE_STATE) : V_ACTIVE_STATE;
                end
                V_FRONT_STATE: begin
                    v_counter <= (line_done == HIGH) ? ((v_counter == (V_FRONT - 10'd1)) ? 10'd0 : (v_counter + 10'd1)) : v_counter;
                    vsync_reg <= HIGH;
                    v_state   <= (line_done == HIGH) ? ((v_counter == (V_FRONT - 10'd1)) ? V_PULSE_STATE : V_FRONT_STATE) : V_FRONT_STATE;
                end
                V_PULSE_STATE: begin
                    v_counter <= (line_done == HIGH) ? ((v_counter == (V_PULSE - 10'd1)) ? 10'd0 : (v_counter + 10'd1)) : v_counter;
                    vsync_reg <= LOW;
                    v_state   <= (line_done == HIGH) ? ((v_counter == (V_PULSE - 10'd1)) ? V_BACK_STATE : V_PULSE_STATE) : V_PULSE_STATE;
                end
                V_BACK_STATE: begin
                    v_counter <= (line_done == HIGH) ? ((v_counter == (V_BACK - 10'd1)) ? 10'd0 : (v_counter + 10'd1)) : v_counter;
                    vsync_reg <= HIGH;
                    v_state   <= (line_done == HIGH) ? ((v_counter == (V_BACK - 10'd1)) ? V_ACTIVE_STATE : V_BACK_STATE) : V_BACK_STATE;
                end
                default: begin
                    v_counter <= 10'd0;
                    vsync_reg <= HIGH;
                    v_state   <= V_ACTIVE_STATE;
                end
            endcase

            if ((h_state == H_ACTIVE_STATE) && (v_state == V_ACTIVE_STATE)) begin
                red_reg   <= {color_in[7:5], 5'd0};
                green_reg <= {color_in[4:2], 5'd0};
                blue_reg  <= {color_in[1:0], 6'd0};
            end else begin
                red_reg   <= 8'd0;
                green_reg <= 8'd0;
                blue_reg  <= 8'd0;
            end
        end
    end

    assign hsync  = hsync_reg;
    assign vsync  = vsync_reg;
    assign red    = red_reg;
    assign green  = green_reg;
    assign blue   = blue_reg;
    assign clk    = clock;
    assign sync   = LOW;
    assign blank  = hsync_reg & vsync_reg;
    assign next_x = (h_state == H_ACTIVE_STATE) ? h_counter : 10'd0;
    assign next_y = (v_state == V_ACTIVE_STATE) ? v_counter : 10'd0;

endmodule
