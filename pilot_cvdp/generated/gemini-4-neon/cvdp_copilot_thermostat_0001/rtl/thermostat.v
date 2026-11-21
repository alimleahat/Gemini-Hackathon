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

    logic       full_cold;
    logic       medium_cold;
    logic       low_cold;
    logic       low_hot;
    logic       medium_hot;
    logic       full_hot;

    logic [2:0] state;
    logic [2:0] next_state;
    logic       fault_latched;
    logic       next_fault;

    assign full_cold   = i_temp_feedback[5];
    assign medium_cold = i_temp_feedback[4];
    assign low_cold    = i_temp_feedback[3];
    assign low_hot     = i_temp_feedback[2];
    assign medium_hot  = i_temp_feedback[1];
    assign full_hot    = i_temp_feedback[0];

    assign o_state = state;

    always_comb begin
        next_fault = fault_latched;
        next_state = state;

        if (i_fault) begin
            next_fault = 1'b1;
            next_state = state;
        end else if (i_clr) begin
            next_fault = 1'b0;
            next_state = AMBIENT;
        end else if (fault_latched) begin
            next_fault = 1'b1;
            next_state = state;
        end else if (!i_enable) begin
            next_fault = 1'b0;
            next_state = AMBIENT;
        end else begin
            next_fault = 1'b0;
            if (full_cold) begin
                next_state = HEAT_FULL;
            end else if (medium_cold) begin
                next_state = HEAT_MED;
            end else if (low_cold) begin
                next_state = HEAT_LOW;
            end else if (full_hot) begin
                next_state = COOL_FULL;
            end else if (medium_hot) begin
                next_state = COOL_MED;
            end else if (low_hot) begin
                next_state = COOL_LOW;
            end else begin
                next_state = AMBIENT;
            end
        end
    end

    always_ff @(posedge i_clk or negedge i_rst) begin
        if (!i_rst) begin
            state           <= AMBIENT;
            fault_latched   <= 1'b0;
            o_heater_full   <= 1'b0;
            o_heater_medium <= 1'b0;
            o_heater_low    <= 1'b0;
            o_aircon_full   <= 1'b0;
            o_aircon_medium <= 1'b0;
            o_aircon_low    <= 1'b0;
            o_fan           <= 1'b0;
        end else begin
            state         <= next_state;
            fault_latched <= next_fault;

            if (next_fault || !i_enable) begin
                o_heater_full   <= 1'b0;
                o_heater_medium <= 1'b0;
                o_heater_low    <= 1'b0;
                o_aircon_full   <= 1'b0;
                o_aircon_medium <= 1'b0;
                o_aircon_low    <= 1'b0;
                o_fan           <= 1'b0;
            end else begin
                o_heater_full   <= (next_state == HEAT_FULL);
                o_heater_medium <= (next_state == HEAT_MED);
                o_heater_low    <= (next_state == HEAT_LOW);
                o_aircon_full   <= (next_state == COOL_FULL);
                o_aircon_medium <= (next_state == COOL_MED);
                o_aircon_low    <= (next_state == COOL_LOW);
                o_fan           <= (next_state != AMBIENT) || i_fan_on;
            end
        end
    end

endmodule
