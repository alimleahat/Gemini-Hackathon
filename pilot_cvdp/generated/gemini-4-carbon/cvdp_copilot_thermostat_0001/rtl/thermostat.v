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

    wire i_full_cold   = i_temp_feedback[5];
    wire i_medium_cold = i_temp_feedback[4];
    wire i_low_cold    = i_temp_feedback[3];
    wire i_low_hot     = i_temp_feedback[2];
    wire i_medium_hot  = i_temp_feedback[1];
    wire i_full_hot    = i_temp_feedback[0];

    logic       fault_latched;
    logic       next_fault_latched;
    logic [2:0] next_state;
    logic       next_heater_full;
    logic       next_heater_medium;
    logic       next_heater_low;
    logic       next_aircon_full;
    logic       next_aircon_medium;
    logic       next_aircon_low;
    logic       next_fan;

    always_comb begin
        next_fault_latched = fault_latched;
        next_state         = o_state;

        next_heater_full   = 1'b0;
        next_heater_medium = 1'b0;
        next_heater_low    = 1'b0;
        next_aircon_full   = 1'b0;
        next_aircon_medium = 1'b0;
        next_aircon_low    = 1'b0;
        next_fan           = 1'b0;

        if (i_fault) begin
            next_fault_latched = 1'b1;
            next_state         = o_state;
        end else if (fault_latched) begin
            if (i_clr) begin
                next_fault_latched = 1'b0;
                next_state         = AMBIENT;
                if (i_enable) begin
                    next_fan = i_fan_on;
                end
            end else begin
                next_fault_latched = 1'b1;
                next_state         = o_state;
            end
        end else if (i_clr) begin
            next_state = AMBIENT;
            if (i_enable) begin
                next_fan = i_fan_on;
            end
        end else if (!i_enable) begin
            next_state = AMBIENT;
        end else begin
            if (i_full_cold)        next_state = HEAT_FULL;
            else if (i_medium_cold) next_state = HEAT_MED;
            else if (i_low_cold)    next_state = HEAT_LOW;
            else if (i_full_hot)    next_state = COOL_FULL;
            else if (i_medium_hot)  next_state = COOL_MED;
            else if (i_low_hot)     next_state = COOL_LOW;
            else                    next_state = AMBIENT;

            case (next_state)
                HEAT_FULL: begin
                    next_heater_full = 1'b1;
                    next_fan         = 1'b1;
                end
                HEAT_MED: begin
                    next_heater_medium = 1'b1;
                    next_fan           = 1'b1;
                end
                HEAT_LOW: begin
                    next_heater_low = 1'b1;
                    next_fan        = 1'b1;
                end
                COOL_FULL: begin
                    next_aircon_full = 1'b1;
                    next_fan         = 1'b1;
                end
                COOL_MED: begin
                    next_aircon_medium = 1'b1;
                    next_fan           = 1'b1;
                end
                COOL_LOW: begin
                    next_aircon_low = 1'b1;
                    next_fan        = 1'b1;
                end
                default: begin
                    next_fan = i_fan_on;
                end
            endcase
        end
    end

    always_ff @(posedge i_clk or negedge i_rst) begin
        if (!i_rst) begin
            fault_latched   <= 1'b0;
            o_state         <= AMBIENT;
            o_heater_full   <= 1'b0;
            o_heater_medium <= 1'b0;
            o_heater_low    <= 1'b0;
            o_aircon_full   <= 1'b0;
            o_aircon_medium <= 1'b0;
            o_aircon_low    <= 1'b0;
            o_fan           <= 1'b0;
        end else begin
            fault_latched   <= next_fault_latched;
            o_state         <= next_state;
            o_heater_full   <= next_heater_full;
            o_heater_medium <= next_heater_medium;
            o_heater_low    <= next_heater_low;
            o_aircon_full   <= next_aircon_full;
            o_aircon_medium <= next_aircon_medium;
            o_aircon_low    <= next_aircon_low;
            o_fan           <= next_fan;
        end
    end

endmodule
