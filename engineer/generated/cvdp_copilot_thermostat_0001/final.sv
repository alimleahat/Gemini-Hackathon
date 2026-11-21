module thermostat (
    input  logic [5:0] i_temp_feedback,
    input  logic       i_fan_on,
    input  logic       i_enable,
    input  logic       i_fault,
    input  logic       i_clr,
    input  logic       i_clk,
    input  logic       i_rst,
    output logic       o_heater_full,
    output logic       o_heater_medium,
    output logic       o_heater_low,
    output logic       o_aircon_full,
    output logic       o_aircon_medium,
    output logic       o_aircon_low,
    output logic       o_fan,
    output logic [2:0] o_state
);

    localparam logic [2:0] HEAT_LOW  = 3'b000;
    localparam logic [2:0] HEAT_MED  = 3'b001;
    localparam logic [2:0] HEAT_FULL = 3'b010;
    localparam logic [2:0] AMBIENT   = 3'b011;
    localparam logic [2:0] COOL_LOW  = 3'b100;
    localparam logic [2:0] COOL_MED  = 3'b101;
    localparam logic [2:0] COOL_FULL = 3'b110;

    logic       active;
    logic       next_active;
    logic       any_temp;
    logic       run_active;
    logic [2:0] next_state;
    logic       next_fan;

    assign next_active   = ~i_fault & (active | i_clr);
    assign any_temp      = |i_temp_feedback;
    assign run_active    = active & i_enable & any_temp;

    assign next_state[2] = run_active & ~i_temp_feedback[5] & ~i_temp_feedback[4] & ~i_temp_feedback[3];
    assign next_state[1] = ~run_active | i_temp_feedback[5] | (~i_temp_feedback[4] & ~i_temp_feedback[3] & i_temp_feedback[0]);
    assign next_state[0] = ~run_active | (~i_temp_feedback[5] & (i_temp_feedback[4] | (~i_temp_feedback[3] & ~i_temp_feedback[0] & i_temp_feedback[1])));
    assign next_fan      = next_active & ((i_enable & i_fan_on) | run_active);

    always_ff @(posedge i_clk or negedge i_rst) begin
        if (!i_rst) begin
            active  <= 1'b1;
            o_state <= AMBIENT;
            o_fan   <= 1'b0;
        end else begin
            active <= next_active;
            o_fan  <= next_fan;
            if (next_active) begin
                o_state <= next_state;
            end
        end
    end

    assign o_heater_low    = active & (o_state == HEAT_LOW);
    assign o_heater_medium = active & (o_state == HEAT_MED);
    assign o_heater_full   = active & (o_state == HEAT_FULL);
    assign o_aircon_low    = active & (o_state == COOL_LOW);
    assign o_aircon_medium = active & (o_state == COOL_MED);
    assign o_aircon_full   = active & (o_state == COOL_FULL);

endmodule
