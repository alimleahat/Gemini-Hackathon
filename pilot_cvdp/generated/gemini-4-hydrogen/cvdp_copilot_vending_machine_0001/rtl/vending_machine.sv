module vending_machine (
    input  logic       clk,
    input  logic       rst,
    input  logic       item_button,
    input  logic [2:0] item_selected,
    input  logic [3:0] coin_input,
    input  logic       cancel,
    output logic       dispense_item,
    output logic       return_change,
    output logic [4:0] item_price,
    output logic [4:0] change_amount,
    output logic [2:0] dispense_item_id,
    output logic       error,
    output logic       return_money
);

    typedef enum logic [2:0] {
        IDLE               = 3'd0,
        ITEM_SELECTION     = 3'd1,
        PAYMENT_VALIDATION = 3'd2,
        DISPENSING_ITEM    = 3'd3,
        RETURN_CHANGE      = 3'd4,
        RETURN_MONEY       = 3'd5
    } state_t;

    state_t     state;
    logic       item_button_d;
    logic       cancel_d;
    logic       item_button_posedge;
    logic       cancel_posedge;
    logic [2:0] selected_item_reg;
    logic [5:0] coins_accumulated;
    logic [5:0] next_coins;
    logic [5:0] change_diff;
    logic       valid_coin;

    assign item_button_posedge = item_button & ~item_button_d;
    assign cancel_posedge      = cancel & ~cancel_d;
    assign next_coins          = coins_accumulated + {2'b00, coin_input};
    assign change_diff         = coins_accumulated - {1'b0, item_price};
    assign valid_coin          = (coin_input == 4'd1) || (coin_input == 4'd2) ||
                                 (coin_input == 4'd5) || (coin_input == 4'd10);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state             <= IDLE;
            item_button_d     <= 1'b0;
            cancel_d          <= 1'b0;
            selected_item_reg <= 3'b000;
            coins_accumulated <= 6'd0;
            dispense_item     <= 1'b0;
            return_change     <= 1'b0;
            item_price        <= 5'd0;
            change_amount     <= 5'd0;
            dispense_item_id  <= 3'b000;
            error             <= 1'b0;
            return_money      <= 1'b0;
        end else begin
            item_button_d    <= item_button;
            cancel_d         <= cancel;

            dispense_item    <= 1'b0;
            return_change    <= 1'b0;
            change_amount    <= 5'd0;
            dispense_item_id <= 3'b000;
            error            <= 1'b0;
            return_money     <= 1'b0;

            case (state)
                IDLE: begin
                    item_price        <= 5'd0;
                    selected_item_reg <= 3'b000;
                    coins_accumulated <= 6'd0;
                    if (coin_input != 4'd0) begin
                        error        <= 1'b1;
                        return_money <= 1'b0;
                        state        <= RETURN_MONEY;
                    end else if (item_button_posedge) begin
                        state <= ITEM_SELECTION;
                    end
                end

                ITEM_SELECTION: begin
                    if (cancel_posedge) begin
                        error        <= 1'b1;
                        return_money <= (coins_accumulated > 6'd0);
                        state        <= RETURN_MONEY;
                    end else if (coin_input != 4'd0) begin
                        error        <= 1'b1;
                        return_money <= (coins_accumulated > 6'd0);
                        state        <= RETURN_MONEY;
                    end else begin
                        case (item_selected)
                            3'b000: begin
                                state <= ITEM_SELECTION;
                            end
                            3'b001: begin
                                item_price        <= 5'd5;
                                selected_item_reg <= 3'b001;
                                state             <= PAYMENT_VALIDATION;
                            end
                            3'b010: begin
                                item_price        <= 5'd10;
                                selected_item_reg <= 3'b010;
                                state             <= PAYMENT_VALIDATION;
                            end
                            3'b011: begin
                                item_price        <= 5'd15;
                                selected_item_reg <= 3'b011;
                                state             <= PAYMENT_VALIDATION;
                            end
                            3'b100: begin
                                item_price        <= 5'd20;
                                selected_item_reg <= 3'b100;
                                state             <= PAYMENT_VALIDATION;
                            end
                            default: begin
                                error        <= 1'b1;
                                return_money <= (coins_accumulated > 6'd0);
                                state        <= RETURN_MONEY;
                            end
                        endcase
                    end
                end

                PAYMENT_VALIDATION: begin
                    if (cancel_posedge) begin
                        error        <= 1'b1;
                        return_money <= (coins_accumulated > 6'd0);
                        state        <= RETURN_MONEY;
                    end else if (coin_input != 4'd0) begin
                        if (valid_coin) begin
                            coins_accumulated <= next_coins;
                            if (next_coins >= {1'b0, item_price}) begin
                                dispense_item    <= 1'b1;
                                dispense_item_id <= selected_item_reg;
                                state            <= DISPENSING_ITEM;
                            end
                        end else begin
                            error        <= 1'b1;
                            return_money <= (coins_accumulated > 6'd0);
                            state        <= RETURN_MONEY;
                        end
                    end
                end

                DISPENSING_ITEM: begin
                    if (coins_accumulated > {1'b0, item_price}) begin
                        return_change <= 1'b1;
                        change_amount <= change_diff[4:0];
                        state         <= RETURN_CHANGE;
                    end else begin
                        item_price        <= 5'd0;
                        selected_item_reg <= 3'b000;
                        coins_accumulated <= 6'd0;
                        state             <= IDLE;
                    end
                end

                RETURN_CHANGE: begin
                    item_price        <= 5'd0;
                    selected_item_reg <= 3'b000;
                    coins_accumulated <= 6'd0;
                    state             <= IDLE;
                end

                RETURN_MONEY: begin
                    item_price        <= 5'd0;
                    selected_item_reg <= 3'b000;
                    coins_accumulated <= 6'd0;
                    state             <= IDLE;
                end

                default: begin
                    item_price        <= 5'd0;
                    selected_item_reg <= 3'b000;
                    coins_accumulated <= 6'd0;
                    state             <= IDLE;
                end
            endcase
        end
    end

endmodule
