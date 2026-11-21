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

    localparam [4:0] PRICE_ITEM_1 = 5'd5;
    localparam [4:0] PRICE_ITEM_2 = 5'd10;
    localparam [4:0] PRICE_ITEM_3 = 5'd15;
    localparam [4:0] PRICE_ITEM_4 = 5'd20;

    state_t     state;
    logic       item_button_prev;
    logic       cancel_prev;
    logic [5:0] coins_accumulated;
    logic [2:0] selected_item;

    logic       item_button_rising;
    logic       cancel_rising;
    logic       coin_inserted;
    logic       is_valid_coin;
    logic [5:0] next_total;
    logic [5:0] excess_amount;

    always_comb begin
        item_button_rising = item_button & ~item_button_prev;
        cancel_rising      = cancel & ~cancel_prev;
        coin_inserted      = (coin_input != 4'd0);

        case (coin_input)
            4'd1, 4'd2, 4'd5, 4'd10: is_valid_coin = 1'b1;
            default:                 is_valid_coin = 1'b0;
        endcase

        next_total    = coins_accumulated + {2'b00, coin_input};
        excess_amount = coins_accumulated - {1'b0, item_price};
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state             <= IDLE;
            item_button_prev  <= 1'b0;
            cancel_prev       <= 1'b0;
            coins_accumulated <= 6'd0;
            selected_item     <= 3'd0;
            dispense_item     <= 1'b0;
            return_change     <= 1'b0;
            item_price        <= 5'd0;
            change_amount     <= 5'd0;
            dispense_item_id  <= 3'd0;
            error             <= 1'b0;
            return_money      <= 1'b0;
        end else begin
            item_button_prev <= item_button;
            cancel_prev      <= cancel;

            dispense_item    <= 1'b0;
            return_change    <= 1'b0;
            error            <= 1'b0;
            return_money     <= 1'b0;

            case (state)
                IDLE: begin
                    coins_accumulated <= 6'd0;
                    selected_item     <= 3'd0;
                    item_price        <= 5'd0;
                    change_amount     <= 5'd0;
                    dispense_item_id  <= 3'd0;

                    if (item_button_rising) begin
                        state <= ITEM_SELECTION;
                    end else if (coin_inserted) begin
                        error        <= 1'b1;
                        return_money <= 1'b1;
                        state        <= RETURN_MONEY;
                    end
                end

                ITEM_SELECTION: begin
                    if (cancel_rising) begin
                        error        <= 1'b1;
                        return_money <= (coins_accumulated > 6'd0) || coin_inserted;
                        state        <= RETURN_MONEY;
                    end else begin
                        case (item_selected)
                            3'b000: begin
                                if (coin_inserted) begin
                                    error        <= 1'b1;
                                    return_money <= 1'b1;
                                    state        <= RETURN_MONEY;
                                end
                            end
                            3'b001: begin
                                selected_item <= 3'b001;
                                item_price    <= PRICE_ITEM_1;
                                state         <= PAYMENT_VALIDATION;
                            end
                            3'b010: begin
                                selected_item <= 3'b010;
                                item_price    <= PRICE_ITEM_2;
                                state         <= PAYMENT_VALIDATION;
                            end
                            3'b011: begin
                                selected_item <= 3'b011;
                                item_price    <= PRICE_ITEM_3;
                                state         <= PAYMENT_VALIDATION;
                            end
                            3'b100: begin
                                selected_item <= 3'b100;
                                item_price    <= PRICE_ITEM_4;
                                state         <= PAYMENT_VALIDATION;
                            end
                            default: begin
                                error        <= 1'b1;
                                return_money <= (coins_accumulated > 6'd0) || coin_inserted;
                                state        <= RETURN_MONEY;
                            end
                        endcase
                    end
                end

                PAYMENT_VALIDATION: begin
                    if (cancel_rising) begin
                        error        <= 1'b1;
                        return_money <= (coins_accumulated > 6'd0) || coin_inserted;
                        state        <= RETURN_MONEY;
                    end else if (coin_inserted) begin
                        if (is_valid_coin) begin
                            coins_accumulated <= next_total;
                            if (next_total >= {1'b0, item_price}) begin
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
                    dispense_item_id <= 3'd0;
                    if (coins_accumulated > {1'b0, item_price}) begin
                        change_amount <= excess_amount[4:0];
                        return_change <= 1'b1;
                        state         <= RETURN_CHANGE;
                    end else begin
                        coins_accumulated <= 6'd0;
                        selected_item     <= 3'd0;
                        item_price        <= 5'd0;
                        change_amount     <= 5'd0;
                        state             <= IDLE;
                    end
                end

                RETURN_CHANGE: begin
                    coins_accumulated <= 6'd0;
                    selected_item     <= 3'd0;
                    item_price        <= 5'd0;
                    change_amount     <= 5'd0;
                    dispense_item_id  <= 3'd0;
                    state             <= IDLE;
                end

                RETURN_MONEY: begin
                    coins_accumulated <= 6'd0;
                    selected_item     <= 3'd0;
                    item_price        <= 5'd0;
                    change_amount     <= 5'd0;
                    dispense_item_id  <= 3'd0;
                    state             <= IDLE;
                end

                default: begin
                    coins_accumulated <= 6'd0;
                    selected_item     <= 3'd0;
                    item_price        <= 5'd0;
                    change_amount     <= 5'd0;
                    dispense_item_id  <= 3'd0;
                    state             <= IDLE;
                end
            endcase
        end
    end

endmodule
