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

    // State encoding (2 bits, disambiguated with selected_item != 0):
    //   st=2'b00, has_item=0 : IDLE
    //   st=2'b00, has_item=1 : PAYMENT_VALIDATION
    //   st=2'b01, has_item=0 : ITEM_SELECTION
    //   st=2'b01, has_item=1 : DISPENSING_ITEM
    //   st=2'b10             : RETURN_CHANGE
    //   st=2'b11             : RETURN_MONEY (paid_any holds return_money)
    logic [1:0] st;
    logic [2:0] selected_item;
    logic [4:0] rem;
    logic       paid_any;
    logic       item_button_prev;
    logic       cancel_prev;

    logic       item_button_rising;
    logic       cancel_rising;
    logic       coin_inserted;
    logic       is_valid_coin;
    logic       valid_item;
    logic       item_sel_err;
    logic       has_item;

    logic [4:0] sub4;
    logic       payment_done;

    logic       load_item;
    logic       pay_valid;
    logic       st0_err;
    logic       st0_d0;
    logic [1:0] next_st;
    logic       next_paid_any;

    always_comb begin
        item_button_rising = item_button & ~item_button_prev;
        cancel_rising      = cancel & ~cancel_prev;
        coin_inserted      = |coin_input;
        is_valid_coin      = (coin_input == 4'd1) | (coin_input == 4'd2) |
                             (coin_input == 4'd5) | (coin_input == 4'd10);

        valid_item         = (item_selected != 3'd0) &
                             (~item_selected[2] | (~item_selected[1] & ~item_selected[0]));
        item_sel_err       = cancel_rising |
                             (item_selected[2] & (item_selected[1] | item_selected[0])) |
                             ((item_selected == 3'd0) & coin_inserted);

        has_item           = |selected_item;

        // 4-bit subtraction: sub4[4] = ~borrow4, sub4[3:0] = rem[3:0] - coin_input
        sub4               = {1'b0, rem[3:0]} + {1'b0, ~coin_input} + 5'd1;
        payment_done       = ~rem[4] & (~sub4[4] | ~(|sub4[3:0]));

        load_item          = ~st[1] & st[0] & ~has_item & ~cancel_rising & valid_item;
        pay_valid          = ~st[1] & ~st[0] & has_item & ~cancel_rising & is_valid_coin;

        st0_err            = has_item ? (cancel_rising | (coin_inserted & ~is_valid_coin))
                                      : (~item_button_rising & coin_inserted);
        st0_d0             = has_item ? (pay_valid & payment_done)
                                      : item_button_rising;

        next_st[1]         = ~st[1] & (st[0] ? (has_item ? rem[4] : item_sel_err) : st0_err);
        next_st[0]         = ~st[1] & (st[0] ? (~has_item & ~load_item) : (next_st[1] | st0_d0));
        next_paid_any      = ~st[1] & ((~st[0] & (paid_any | pay_valid)) | (next_st[1] & coin_inserted));

        // Pure Moore outputs (depend only on FFs)
        dispense_item      = ~st[1] & st[0] & has_item;
        dispense_item_id   = {3{dispense_item}} & selected_item;
        return_change      = st[1] & ~st[0];
        error              = st[1] & st[0];
        return_money       = error & paid_any;

        // item_price = selected_item * 5 for selected_item in 0..4
        item_price         = {selected_item[2],
                              selected_item[1],
                              selected_item[2] | selected_item[0],
                              selected_item[1],
                              selected_item[0]};

        // In RETURN_CHANGE, rem[3:0] holds 2's complement of -change (change in 1..9)
        change_amount[0]   = return_change & rem[0];
        change_amount[1]   = return_change & (rem[1] ^ rem[0]);
        change_amount[2]   = return_change & (rem[2] ^ (rem[1] | rem[0]));
        change_amount[3]   = return_change & (rem[3] ^ (rem[2] | rem[1] | rem[0]));
        change_amount[4]   = 1'b0;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            st               <= 2'b00;
            selected_item    <= 3'd0;
            rem              <= 5'd0;
            paid_any         <= 1'b0;
            item_button_prev <= 1'b0;
            cancel_prev      <= 1'b0;
        end else begin
            item_button_prev <= item_button;
            cancel_prev      <= cancel;
            st               <= next_st;
            paid_any         <= next_paid_any;

            selected_item    <= load_item ? item_selected
                                          : ({3{~st[1] & (~st[0] | rem[4])}} & selected_item);

            if (load_item) begin
                rem <= {item_selected[2],
                        item_selected[1],
                        item_selected[2] | item_selected[0],
                        item_selected[1],
                        item_selected[0]};
            end else if (pay_valid) begin
                rem <= {rem[4] ^ ~sub4[4], sub4[3:0]};
            end
        end
    end

endmodule
