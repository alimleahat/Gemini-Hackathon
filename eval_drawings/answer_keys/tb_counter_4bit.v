// Reference Answer Key: 4-Bit Binary Up-Counter
// Expected behavior:
//   1. Reset sets count == 0.
//   2. On each rising clock edge (with enable=1 if present), count increments by 1
//      through all 16 states 0..15 and wraps around 15 -> 0.
//   3. Mid-count reset returns count to 0.
module tb_counter_4bit_ref;
  reg clk = 0;
  reg rst = 0;
  reg en  = 1;
  wire [3:0] count;

  counter_4bit dut (.clk(clk), .rst(rst), .en(en), .count(count));

  integer i;
  integer errors = 0;

  task tick;
    begin
      #5 clk = 1;
      #5 clk = 0;
      #1;
    end
  endtask

  initial begin
    // 1. Reset to 0
    rst = 1; en = 1;
    tick();
    rst = 0;
    if (count !== 4'd0) begin
      $display("FAIL: after reset got count=%0d expected 0", count);
      errors = errors + 1;
    end

    // 2. Count through all 16 states + wrap-around (1..15, 0)
    for (i = 1; i <= 16; i = i + 1) begin
      tick();
      if (count !== (i % 16)) begin
        $display("FAIL: cycle %0d got count=%0d expected %0d", i, count, i % 16);
        errors = errors + 1;
      end
    end

    // 3. Advance 3 cycles then mid-count reset
    tick(); tick(); tick();
    rst = 1;
    tick();
    rst = 0;
    if (count !== 4'd0) begin
      $display("FAIL: after mid-count reset got count=%0d expected 0", count);
      errors = errors + 1;
    end

    if (errors == 0) $display("ANSWER_KEY_PASS (all 16 states + wrap + reset)");
    else $display("ANSWER_KEY_FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
