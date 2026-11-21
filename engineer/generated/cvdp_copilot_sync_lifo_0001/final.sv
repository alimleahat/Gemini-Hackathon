module sync_lifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 3
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

    localparam DEPTH = 1 << ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH:0]   sp;
    logic [ADDR_WIDTH:0]   sp_next;
    logic [ADDR_WIDTH-1:0] mem_addr;
    logic [ADDR_WIDTH-1:0] borrow;
    logic [ADDR_WIDTH:0]   c_inc;
    logic [ADDR_WIDTH:0]   c_dec;
    logic                  do_write;
    logic                  do_read;

    assign empty    = ~(|sp);
    assign full     = sp[ADDR_WIDTH];
    assign do_write = write_en & ~full;
    assign do_read  = read_en  & ~empty;

    assign borrow[0] = do_read;
    assign c_inc[0]  = do_write & ~do_read;
    assign c_dec[0]  = do_read  & ~do_write;

    genvar k;
    generate
        for (k = 1; k < ADDR_WIDTH; k = k + 1) begin : gen_borrow
            assign borrow[k] = borrow[k-1] & ~sp[k-1];
        end
        for (k = 1; k <= ADDR_WIDTH; k = k + 1) begin : gen_carry
            assign c_inc[k] = c_inc[k-1] &  sp[k-1];
            assign c_dec[k] = c_dec[k-1] & ~sp[k-1];
        end
    endgenerate

    assign mem_addr = sp[ADDR_WIDTH-1:0] ^ borrow;
    assign sp_next  = sp ^ (c_inc | c_dec);

    always_ff @(posedge clock) begin
        if (do_write) begin
            mem[mem_addr] <= data_in;
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            sp       <= {(ADDR_WIDTH+1){1'b0}};
            data_out <= {DATA_WIDTH{1'b0}};
        end else begin
            sp <= sp_next;
            if (do_read) begin
                data_out <= mem[mem_addr];
            end
        end
    end

endmodule
