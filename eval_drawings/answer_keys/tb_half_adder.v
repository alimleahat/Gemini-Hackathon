// Reference Answer Key: Half Adder (Exhaustive 4/4 truth table)
// Expected behavior:
//   sum   = a ^ b
//   carry = a & b
module tb_half_adder_ref;
  reg a = 0;
  reg b = 0;
  wire sum;
  wire carry;

  // Instantiate DUT (port names are bound automatically by eval_drawings/answer_keys.py)
  half_adder dut (.a(a), .b(b), .sum(sum), .carry(carry));

  integer i;
  integer errors = 0;
  reg exp_sum, exp_carry;

  initial begin
    for (i = 0; i < 4; i = i + 1) begin
      a = i[0];
      b = i[1];
      #10;
      exp_sum   = a ^ b;
      exp_carry = a & b;
      if (sum !== exp_sum || carry !== exp_carry) begin
        $display("FAIL: a=%b b=%b | got sum=%b carry=%b | exp sum=%b carry=%b",
                 a, b, sum, carry, exp_sum, exp_carry);
        errors = errors + 1;
      end
    end
    if (errors == 0) $display("ANSWER_KEY_PASS (4/4)");
    else $display("ANSWER_KEY_FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
