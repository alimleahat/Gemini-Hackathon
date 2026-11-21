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

    localparam int            DEPTH     = 1 << ADDR_WIDTH;
    localparam [ADDR_WIDTH:0] DEPTH_VAL = {1'b1, {ADDR_WIDTH{1'b0}}};
    localparam [ADDR_WIDTH:0] ZERO_PTR  = {(ADDR_WIDTH+1){1'b0}};
    localparam [ADDR_WIDTH:0] ONE_PTR   = {{ADDR_WIDTH{1'b0}}, 1'b1};

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH:0]   sp;
    logic [ADDR_WIDTH:0]   sp_dec;
    logic                  do_write;
    logic                  do_read;

    assign empty    = (sp == ZERO_PTR);
    assign full     = (sp == DEPTH_VAL);
    assign sp_dec   = sp - ONE_PTR;
    assign do_write = write_en && !full;
    assign do_read  = read_en  && !empty;

    always_ff @(posedge clock) begin
        if (reset) begin
            sp       <= ZERO_PTR;
            data_out <= {DATA_WIDTH{1'b0}};
            for (int i = 0; i < DEPTH; i = i + 1) begin
                mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            case ({do_write, do_read})
                2'b10: begin
                    mem[sp[ADDR_WIDTH-1:0]] <= data_in;
                    sp                      <= sp + ONE_PTR;
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
                end
            endcase
        end
    end

endmodule
