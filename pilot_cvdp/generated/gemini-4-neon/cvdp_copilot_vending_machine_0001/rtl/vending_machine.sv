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
    logic       item_button_prev;
    logic       cancel_prev;
    logic       item_button_rising;
    logic       cancel_rising;

    logic [2:0] selected_item;
    logic [5:0] coins_accumulated;
    logic [5:0] next_coins;
    logic [5:0] change_calc;
    logic       is_valid_coin;
    logic       is_valid_item;
    logic [4:0] selected_price;

    assign item_button_rising = item_button & ~item_button_prev;
    assign cancel_rising      = cancel & ~cancel_prev;
    assign next_coins         = coins_accumulated + {2'b00, coin_input};
    assign change_calc        = coins_accumulated - {1'b0, item_price};

    always_comb begin
        case (coin_input)
            4'd1, 4'd2, 4'd5, 4'd10: is_valid_coin = 1'b1;
            default:                 is_valid_coin = 1'b0;
        endcase
    end

    always_comb begin
        case (item_selected)
            3'b001: begin
                is_valid_item  = 1'b1;
                selected_price = 5'd5;
            end
            3'b010: begin
                is_valid_item  = 1'b1;
                selected_price = 5'd10;
            end
            3'b011: begin
                is_valid_item  = 1'b1;
                selected_price = 5'd15;
            end
            3'b100: begin
                is_valid_item  = 1'b1;
                selected_price = 5'd20;
            end
            default: begin
                is_valid_item  = 1'b0;
                selected_price = 5'd0;
            end
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state             <= IDLE;
            item_button_prev  <= 1'b0;
            cancel_prev       <= 1'b0;
            selected_item     <= 3'd0;
            coins_accumulated <= 6'd0;
            item_price        <= 5'd0;
            dispense_item     <= 1'b0;
            dispense_item_id  <= 3'd0;
            return_change     <= 1'b0;
            change_amount     <= 5'd0;
            error             <= 1'b0;
            return_money      <= 1'b0;
        end else begin
            item_button_prev <= item_button;
            cancel_prev      <= cancel;

            dispense_item    <= 1'b0;
            dispense_item_id <= 3'd0;
            return_change    <= 1'b0;
            change_amount    <= 5'd0;
            error            <= 1'b0;
            return_money     <= 1'b0;

            case (state)
                IDLE: begin
                    selected_item     <= 3'd0;
                    coins_accumulated <= 6'd0;
                    item_price        <= 5'd0;
                    if (item_button_rising) begin
                        state <= ITEM_SELECTION;
                    end else if (coin_input != 4'd0) begin
                        error        <= 1'b1;
                        return_money <= 1'b1;
                        state        <= RETURN_MONEY;
                    end
                end

                ITEM_SELECTION: begin
                    if (cancel_rising) begin
                        error        <= 1'b1;
                        return_money <= (coins_accumulated != 6'd0) || (coin_input != 4'd0);
                        state        <= RETURN_MONEY;
                    end else if (is_valid_item) begin
                        selected_item <= item_selected;
                        item_price    <= selected_price;
                        state         <= PAYMENT_VALIDATION;
                    end else if (item_selected != 3'b000) begin
                        error        <= 1'b1;
                        return_money <= (coins_accumulated != 6'd0) || (coin_input != 4'd0);
                        state        <= RETURN_MONEY;
                    end else if (coin_input != 4'd0) begin
                        error        <= 1'b1;
                        return_money <= 1'b1;
                        state        <= RETURN_MONEY;
                    end
                end

                PAYMENT_VALIDATION: begin
                    if (cancel_rising) begin
                        error        <= 1'b1;
                        return_money <= (coins_accumulated != 6'd0) || (coin_input != 4'd0);
                        state        <= RETURN_MONEY;
                    end else if (coin_input != 4'd0) begin
                        if (is_valid_coin) begin
                            coins_accumulated <= next_coins;
                            if (next_coins >= {1'b0, item_price}) begin
                                dispense_item    <= 1'b1;
                                dispense_item_id <= selected_item;
                                state            <= DISPENSING_ITEM;
                            end
                        end else begin
                            error        <= 1'b1;
                            return_money <= 1'b1;
                            state        <= RETURN_MONEY;
                        end
                    end
                end

                DISPENSING_ITEM: begin
                    if (coins_accumulated > {1'b0, item_price}) begin
                        return_change <= 1'b1;
                        change_amount <= change_calc[4:0];
                        state         <= RETURN_CHANGE;
                    end else begin
                        selected_item     <= 3'd0;
                        coins_accumulated <= 6'd0;
                        item_price        <= 5'd0;
                        state             <= IDLE;
                    end
                end

                RETURN_CHANGE: begin
                    selected_item     <= 3'd0;
                    coins_accumulated <= 6'd0;
                    item_price        <= 5'd0;
                    state             <= IDLE;
                end

                RETURN_MONEY: begin
                    selected_item     <= 3'd0;
                    coins_accumulated <= 6'd0;
                    item_price        <= 5'd0;
                    state             <= IDLE;
                end

                default: begin
                    selected_item     <= 3'd0;
                    coins_accumulated <= 6'd0;
                    item_price        <= 5'd0;
                    state             <= IDLE;
                end
            endcase
        end
    end

endmodule
