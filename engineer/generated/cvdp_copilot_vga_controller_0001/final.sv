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
    output logic [9:0] next_x,
    output logic [9:0] next_y,
    output logic       hsync,
    output logic       vsync,
    output logic [7:0] red,
    output logic [7:0] green,
    output logic [7:0] blue,
    output logic       sync,
    output logic       clk,
    output logic       blank
);

    localparam [9:0] H_PULSE_START = H_ACTIVE + H_FRONT;
    localparam [9:0] H_PULSE_END   = H_ACTIVE + H_FRONT + H_PULSE;
    localparam [9:0] H_TOTAL       = H_ACTIVE + H_FRONT + H_PULSE + H_BACK;

    localparam [9:0] V_PULSE_START = V_ACTIVE + V_FRONT;
    localparam [9:0] V_PULSE_END   = V_ACTIVE + V_FRONT + V_PULSE;
    localparam [9:0] V_TOTAL       = V_ACTIVE + V_FRONT + V_PULSE + V_BACK;

    localparam [0:0] DEFAULT_H_ACTIVE = (H_ACTIVE == 10'd640);
    localparam [0:0] DEFAULT_H_PULSE  = (H_PULSE_START == 10'd656) && (H_PULSE_END == 10'd752);
    localparam [0:0] DEFAULT_V_ACTIVE = (V_ACTIVE == 10'd480);
    localparam [0:0] DEFAULT_V_PULSE  = (V_ACTIVE == 10'd480) && (V_FRONT == 10'd10) && (V_PULSE == 10'd2);

    logic [9:0] h_cnt;
    logic [9:0] v_cnt;
    logic [7:0] color_reg;
    logic       hsync_reg;
    logic       vsync_reg;
    logic       blank_reg;

    logic [9:0] h_cnt_inc;
    logic [9:0] v_cnt_inc;
    logic [9:0] h_cnt_nxt;
    logic [9:0] v_cnt_nxt;
    logic       h_end;
    logic       v_end;
    logic       h_active;
    logic       v_active;
    logic       blank_next;
    logic       h_pulse;
    logic       v_pulse;

    assign h_cnt_inc  = h_cnt + 10'd1;
    assign h_end      = (h_cnt == (H_TOTAL - 10'd1));
    assign h_cnt_nxt  = h_cnt_inc & ~(H_TOTAL & {10{h_end}});

    assign v_cnt_inc  = v_cnt + 10'd1;
    assign v_end      = (v_cnt == (V_TOTAL - 10'd1));
    assign v_cnt_nxt  = v_cnt_inc & ~(V_TOTAL & {10{v_end}});

    assign h_active   = DEFAULT_H_ACTIVE
                      ? ~(h_cnt[9] & (h_cnt[8] | h_cnt[7]))
                      : (h_cnt < H_ACTIVE);

    assign v_active   = DEFAULT_V_ACTIVE
                      ? (~v_cnt[9] & ~(&v_cnt[8:5]))
                      : (v_cnt < V_ACTIVE);

    assign blank_next = ~(h_active & v_active);

    assign h_pulse    = DEFAULT_H_PULSE
                      ? (h_cnt[9] & ~h_cnt[8] & h_cnt[7] & (|h_cnt[6:4]) & ~(&h_cnt[6:4]))
                      : ((h_cnt >= H_PULSE_START) && (h_cnt < H_PULSE_END));

    assign v_pulse    = DEFAULT_V_PULSE
                      ? (~v_active & ~v_cnt[9] & ~v_cnt[4] & v_cnt[3] & ~v_cnt[2] & v_cnt[1])
                      : ((v_cnt >= V_PULSE_START) && (v_cnt < V_PULSE_END));

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            h_cnt     <= 10'd0;
            v_cnt     <= 10'd0;
            hsync_reg <= 1'b1;
            vsync_reg <= 1'b1;
            blank_reg <= 1'b1;
            color_reg <= 8'd0;
        end else begin
            h_cnt <= h_cnt_nxt;
            if (h_end) begin
                v_cnt <= v_cnt_nxt;
            end
            hsync_reg <= ~h_pulse;
            vsync_reg <= ~v_pulse;
            blank_reg <= blank_next;
            color_reg <= blank_next ? 8'd0 : color_in;
        end
    end

    assign hsync  = hsync_reg;
    assign vsync  = vsync_reg;
    assign red    = {color_reg[7:5], 5'd0};
    assign green  = {color_reg[4:2], 5'd0};
    assign blue   = {color_reg[1:0], 6'd0};
    assign clk    = clock;
    assign sync   = 1'b0;
    assign blank  = blank_reg;
    assign next_x = blank_next ? 10'd0 : h_cnt;
    assign next_y = v_active ? v_cnt : 10'd0;

endmodule
