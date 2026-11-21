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

    localparam DEPTH = (1 << ADDR_WIDTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH:0]   sp;
    logic [ADDR_WIDTH:0]   sp_dec;
    logic                  do_write;
    logic                  do_read;

    integer i;

    assign empty    = (sp == {(ADDR_WIDTH+1){1'b0}});
    assign full     = sp[ADDR_WIDTH];
    assign sp_dec   = sp - {{ADDR_WIDTH{1'b0}}, 1'b1};
    assign do_write = write_en && !full;
    assign do_read  = read_en  && !empty;

    always_ff @(posedge clock) begin
        if (reset) begin
            sp       <= {(ADDR_WIDTH+1){1'b0}};
            data_out <= {DATA_WIDTH{1'b0}};
            for (i = 0; i < DEPTH; i = i + 1) begin
                mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            case ({do_write, do_read})
                2'b10: begin
                    mem[sp[ADDR_WIDTH-1:0]] <= data_in;
                    sp                      <= sp + {{ADDR_WIDTH{1'b0}}, 1'b1};
                end
                2'b01: begin
                    data_out <= mem[sp_dec[ADDR_WIDTH-1:0]];
                    sp       <= sp_dec;
                end
                2'b11: begin
                    data_out                    <= mem[sp_dec[ADDR_WIDTH-1:0]];
                    mem[sp_dec[ADDR_WIDTH-1:0]] <= data_in;
                end
                default: begin
                    // Hold current state
                end
            endcase
        end
    end

endmodule
