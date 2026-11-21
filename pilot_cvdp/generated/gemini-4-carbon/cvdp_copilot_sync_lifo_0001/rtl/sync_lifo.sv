module sync_lifo #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 3
) (
    input  logic                  clock,
    input  logic                  reset,
    input  logic                  write_en,
    input  logic                  read_en,
    input  logic [DATA_WIDTH-1:0] data_in,
    output logic                  empty,
    output logic                  full,
    output logic [DATA_WIDTH-1:0] data_out
);

    localparam int DEPTH = 1 << ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH:0]   sp;

    logic                  do_write;
    logic                  do_read;
    logic [ADDR_WIDTH-1:0] push_addr;
    logic [ADDR_WIDTH-1:0] pop_addr;

    assign empty     = (sp == '0);
    assign full      = sp[ADDR_WIDTH];

    assign do_write  = write_en && !full;
    assign do_read   = read_en  && !empty;

    assign push_addr = sp[ADDR_WIDTH-1:0];
    assign pop_addr  = sp[ADDR_WIDTH-1:0] - 1'b1;

    integer i;

    always_ff @(posedge clock) begin
        if (reset) begin
            sp       <= '0;
            data_out <= '0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                mem[i] <= '0;
            end
        end else begin
            case ({do_write, do_read})
                2'b10: begin
                    mem[push_addr] <= data_in;
                    sp             <= sp + 1'b1;
                end
                2'b01: begin
                    data_out <= mem[pop_addr];
                    sp       <= sp - 1'b1;
                end
                2'b11: begin
                    data_out      <= mem[pop_addr];
                    mem[pop_addr] <= data_in;
                end
                default: begin
                    // Hold current state
                end
            endcase
        end
    end

endmodule
