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

    localparam [2:0] HEAT_LOW  = 3'b000;
    localparam [2:0] HEAT_MED  = 3'b001;
    localparam [2:0] HEAT_FULL = 3'b010;
    localparam [2:0] AMBIENT   = 3'b011;
    localparam [2:0] COOL_LOW  = 3'b100;
    localparam [2:0] COOL_MED  = 3'b101;
    localparam [2:0] COOL_FULL = 3'b110;

    logic [2:0] r_state;
    logic [2:0] next_state;
    logic       r_fault;
    logic       next_fault;

    assign o_state = r_state;

    always_comb begin
        next_fault = r_fault;
        next_state = r_state;

        if (i_fault) begin
            next_fault = 1'b1;
        end else if (r_fault) begin
            if (i_clr) begin
                next_fault = 1'b0;
                next_state = AMBIENT;
            end
        end else if (!i_enable) begin
            next_state = AMBIENT;
        end else begin
            if (i_temp_feedback[5]) begin
                next_state = HEAT_FULL;
            end else if (i_temp_feedback[4]) begin
                next_state = HEAT_MED;
            end else if (i_temp_feedback[3]) begin
                next_state = HEAT_LOW;
            end else if (i_temp_feedback[0]) begin
                next_state = COOL_FULL;
            end else if (i_temp_feedback[1]) begin
                next_state = COOL_MED;
            end else if (i_temp_feedback[2]) begin
                next_state = COOL_LOW;
            end else begin
                next_state = AMBIENT;
            end
        end
    end

    always_ff @(posedge i_clk or negedge i_rst) begin
        if (!i_rst) begin
            r_fault         <= 1'b0;
            r_state         <= AMBIENT;
            o_heater_full   <= 1'b0;
            o_heater_medium <= 1'b0;
            o_heater_low    <= 1'b0;
            o_aircon_full   <= 1'b0;
            o_aircon_medium <= 1'b0;
            o_aircon_low    <= 1'b0;
            o_fan           <= 1'b0;
        end else begin
            r_fault         <= next_fault;
            r_state         <= next_state;
            o_heater_full   <= 1'b0;
            o_heater_medium <= 1'b0;
            o_heater_low    <= 1'b0;
            o_aircon_full   <= 1'b0;
            o_aircon_medium <= 1'b0;
            o_aircon_low    <= 1'b0;
            o_fan           <= 1'b0;

            if (!next_fault && i_enable) begin
                case (next_state)
                    HEAT_FULL: begin
                        o_heater_full <= 1'b1;
                        o_fan         <= 1'b1;
                    end
                    HEAT_MED: begin
                        o_heater_medium <= 1'b1;
                        o_fan           <= 1'b1;
                    end
                    HEAT_LOW: begin
                        o_heater_low <= 1'b1;
                        o_fan        <= 1'b1;
                    end
                    COOL_FULL: begin
                        o_aircon_full <= 1'b1;
                        o_fan         <= 1'b1;
                    end
                    COOL_MED: begin
                        o_aircon_medium <= 1'b1;
                        o_fan           <= 1'b1;
                    end
                    COOL_LOW: begin
                        o_aircon_low <= 1'b1;
                        o_fan        <= 1'b1;
                    end
                    AMBIENT: begin
                        o_fan <= i_fan_on;
                    end
                    default: begin
                        o_fan <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule
