// Reference Answer Key: 4-Bit Adder with 7-Segment Output (Exhaustive 256 cases)
// Expected behavior:
//   sum[3:0] = (a[3:0] + b[3:0])[3:0]
//   seg[6:0] = active-low 7-segment hex encoding of sum[3:0] (bit 0=a .. bit 6=g, 0=ON)
//   an[3:0]  = active-low digit enable (at least digit 0 enabled: an[0] == 0)
module tb_adder_4bit_7seg_ref;
  reg [3:0] a = 0;
  reg [3:0] b = 0;
  wire [6:0] seg;
  wire [3:0] an;

  adder_4bit_7seg dut (.a(a), .b(b), .seg(seg), .an(an));

  function [6:0] hex_to_seg;
    input [3:0] val;
    begin
      case (val)
        4'h0: hex_to_seg = 7'b1000000;
        4'h1: hex_to_seg = 7'b1111001;
        4'h2: hex_to_seg = 7'b0100100;
        4'h3: hex_to_seg = 7'b0110000;
        4'h4: hex_to_seg = 7'b0011001;
        4'h5: hex_to_seg = 7'b0010010;
        4'h6: hex_to_seg = 7'b0000010;
        4'h7: hex_to_seg = 7'b1111000;
        4'h8: hex_to_seg = 7'b0000000;
        4'h9: hex_to_seg = 7'b0010000;
        4'hA: hex_to_seg = 7'b0001000;
        4'hB: hex_to_seg = 7'b0000011;
        4'hC: hex_to_seg = 7'b1000110;
        4'hD: hex_to_seg = 7'b0100001;
        4'hE: hex_to_seg = 7'b0000110;
        4'hF: hex_to_seg = 7'b0001110;
      endcase
    end
  endfunction

  integer ia, ib;
  integer errors = 0;
  reg [3:0] exp_sum;
  reg [6:0] exp_seg;

  initial begin
    for (ia = 0; ia < 16; ia = ia + 1) begin
      for (ib = 0; ib < 16; ib = ib + 1) begin
        a = ia[3:0];
        b = ib[3:0];
        #10;
        exp_sum = ia + ib;
        exp_seg = hex_to_seg(exp_sum);
        if (seg !== exp_seg) begin
          if (errors < 10)
            $display("FAIL: a=%0d b=%0d (sum=%h) | got seg=%b | exp seg=%b",
                     a, b, exp_sum, seg, exp_seg);
          errors = errors + 1;
        end
      end
    end
    if (errors == 0) $display("ANSWER_KEY_PASS (256/256)");
    else $display("ANSWER_KEY_FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
