// Reference Answer Key: Full Adder (Exhaustive 8/8 truth table)
// Expected behavior:
//   {cout, sum} = a + b + cin
module tb_full_adder_ref;
  reg a = 0;
  reg b = 0;
  reg cin = 0;
  wire sum;
  wire cout;

  full_adder dut (.a(a), .b(b), .cin(cin), .sum(sum), .cout(cout));

  integer i;
  integer errors = 0;
  reg [1:0] exp_res;

  initial begin
    for (i = 0; i < 8; i = i + 1) begin
      a   = i[0];
      b   = i[1];
      cin = i[2];
      #10;
      exp_res = a + b + cin;
      if (sum !== exp_res[0] || cout !== exp_res[1]) begin
        $display("FAIL: a=%b b=%b cin=%b | got sum=%b cout=%b | exp sum=%b cout=%b",
                 a, b, cin, sum, cout, exp_res[0], exp_res[1]);
        errors = errors + 1;
      end
    end
    if (errors == 0) $display("ANSWER_KEY_PASS (8/8)");
    else $display("ANSWER_KEY_FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
