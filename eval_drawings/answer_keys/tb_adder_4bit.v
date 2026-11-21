// Reference Answer Key: 4-Bit Ripple-Carry Adder (Exhaustive 256 or 512 cases)
// Expected behavior:
//   {cout, sum[3:0]} = a[3:0] + b[3:0] + cin
module tb_adder_4bit_ref;
  reg [3:0] a = 0;
  reg [3:0] b = 0;
  reg cin = 0;
  wire [3:0] sum;
  wire cout;

  adder_4bit dut (.a(a), .b(b), .cin(cin), .sum(sum), .cout(cout));

  integer ia, ib, ic;
  integer errors = 0;
  reg [4:0] exp_res;

  initial begin
    for (ic = 0; ic < 2; ic = ic + 1) begin
      for (ia = 0; ia < 16; ia = ia + 1) begin
        for (ib = 0; ib < 16; ib = ib + 1) begin
          a = ia[3:0];
          b = ib[3:0];
          cin = ic[0];
          #10;
          exp_res = {1'b0, a} + {1'b0, b} + {4'b0, cin};
          if (sum !== exp_res[3:0] || cout !== exp_res[4]) begin
            if (errors < 10)
              $display("FAIL: a=%0d b=%0d cin=%b | got sum=%0d cout=%b | exp sum=%0d cout=%b",
                       a, b, cin, sum, cout, exp_res[3:0], exp_res[4]);
            errors = errors + 1;
          end
        end
      end
    end
    if (errors == 0) $display("ANSWER_KEY_PASS (512/512)");
    else $display("ANSWER_KEY_FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
