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
    logic [5:0] coins_accumulated;
    logic [2:0] selected_item;

    wire item_button_posedge = item_button && !item_button_prev;
    wire cancel_posedge      = cancel && !cancel_prev;

    wire coin_inserted = (coin_input != 4'd0);
    wire coin_valid    = (coin_input == 4'd1) ||
                         (coin_input == 4'd2) ||
                         (coin_input == 4'd5) ||
                         (coin_input == 4'd10);

    wire item_nonzero  = (item_selected != 3'b000);
    wire item_valid    = (item_selected >= 3'b001) && (item_selected <= 3'b100);

    logic [4:0] lookup_price;
    always_comb begin
        case (item_selected)
            3'b001:  lookup_price = 5'd5;
            3'b010:  lookup_price = 5'd10;
            3'b011:  lookup_price = 5'd15;
            3'b100:  lookup_price = 5'd20;
            default: lookup_price = 5'd0;
        endcase
    end

    wire [5:0] next_coins  = coins_accumulated + {2'b00, coin_input};
    wire [5:0] diff_change = coins_accumulated - {1'b0, item_price};

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

            dispense_item <= 1'b0;
            return_change <= 1'b0;
            error         <= 1'b0;
            return_money  <= 1'b0;

            case (state)
                IDLE: begin
                    item_price        <= 5'd0;
                    change_amount     <= 5'd0;
                    dispense_item_id  <= 3'd0;
                    coins_accumulated <= 6'd0;
                    selected_item     <= 3'd0;

                    if (coin_inserted) begin
                        error        <= 1'b1;
                        return_money <= 1'b1;
                        state        <= RETURN_MONEY;
                    end else if (item_button_posedge) begin
                        state <= ITEM_SELECTION;
                    end
                end

                ITEM_SELECTION: begin
                    if (cancel_posedge) begin
                        error        <= 1'b1;
                        return_money <= (coins_accumulated > 6'd0) || coin_inserted;
                        state        <= RETURN_MONEY;
                    end else if (coin_inserted) begin
                        error        <= 1'b1;
                        return_money <= 1'b1;
                        state        <= RETURN_MONEY;
                    end else if (item_nonzero) begin
                        if (item_valid) begin
                            selected_item <= item_selected;
                            item_price    <= lookup_price;
                            state         <= PAYMENT_VALIDATION;
                        end else begin
                            error        <= 1'b1;
                            return_money <= (coins_accumulated > 6'd0);
                            state        <= RETURN_MONEY;
                        end
                    end
                end

                PAYMENT_VALIDATION: begin
                    if (cancel_posedge) begin
                        error        <= 1'b1;
                        return_money <= (coins_accumulated > 6'd0) || coin_inserted;
                        state        <= RETURN_MONEY;
                    end else if (coin_inserted) begin
                        if (coin_valid) begin
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
                    dispense_item_id <= 3'd0;
                    if (coins_accumulated > {1'b0, item_price}) begin
                        return_change <= 1'b1;
                        change_amount <= diff_change[4:0];
                        state         <= RETURN_CHANGE;
                    end else begin
                        item_price        <= 5'd0;
                        change_amount     <= 5'd0;
                        coins_accumulated <= 6'd0;
                        selected_item     <= 3'd0;
                        state             <= IDLE;
                    end
                end

                RETURN_CHANGE: begin
                    item_price        <= 5'd0;
                    change_amount     <= 5'd0;
                    dispense_item_id  <= 3'd0;
                    coins_accumulated <= 6'd0;
                    selected_item     <= 3'd0;
                    state             <= IDLE;
                end

                RETURN_MONEY: begin
                    item_price        <= 5'd0;
                    change_amount     <= 5'd0;
                    dispense_item_id  <= 3'd0;
                    coins_accumulated <= 6'd0;
                    selected_item     <= 3'd0;
                    state             <= IDLE;
                end

                default: begin
                    item_price        <= 5'd0;
                    change_amount     <= 5'd0;
                    dispense_item_id  <= 3'd0;
                    coins_accumulated <= 6'd0;
                    selected_item     <= 3'd0;
                    state             <= IDLE;
                end
            endcase
        end
    end

endmodule
