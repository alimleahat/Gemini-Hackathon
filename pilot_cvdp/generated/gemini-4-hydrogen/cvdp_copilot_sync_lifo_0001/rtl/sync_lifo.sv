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

    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [ADDR_WIDTH-1:0] rd_addr;
    logic                  do_write;
    logic                  do_read;

    integer i;

    assign empty    = (sp == {ADDR_WIDTH+1{1'b0}});
    assign full     = (sp == DEPTH[ADDR_WIDTH:0]);
    assign wr_addr  = sp[ADDR_WIDTH-1:0];
    assign rd_addr  = sp[ADDR_WIDTH-1:0] - {{ADDR_WIDTH-1{1'b0}}, 1'b1};
    assign do_write = write_en && !full;
    assign do_read  = read_en  && !empty;

    always_ff @(posedge clock) begin
        if (reset) begin
            sp       <= {ADDR_WIDTH+1{1'b0}};
            data_out <= {DATA_WIDTH{1'b0}};
            for (i = 0; i < DEPTH; i = i + 1) begin
                mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            if (do_write && do_read) begin
                data_out     <= mem[rd_addr];
                mem[rd_addr] <= data_in;
            end else if (do_write) begin
                mem[wr_addr] <= data_in;
                sp           <= sp + {{ADDR_WIDTH{1'b0}}, 1'b1};
            end else if (do_read) begin
                data_out     <= mem[rd_addr];
                sp           <= sp - {{ADDR_WIDTH{1'b0}}, 1'b1};
            end
        end
    end

endmodule
