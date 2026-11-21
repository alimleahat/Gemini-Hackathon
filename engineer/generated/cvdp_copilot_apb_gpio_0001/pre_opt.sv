module cvdp_copilot_apb_gpio #(
    parameter int GPIO_WIDTH = 8
) (
    input  logic                    pclk,
    input  logic                    preset_n,
    input  logic                    psel,
    input  logic [7:2]              paddr,
    input  logic                    penable,
    input  logic                    pwrite,
    input  logic [31:0]             pwdata,
    input  logic [GPIO_WIDTH-1:0]   gpio_in,

    output logic [31:0]             prdata,
    output logic                    pready,
    output logic                    pslverr,
    output logic [GPIO_WIDTH-1:0]   gpio_out,
    output logic [GPIO_WIDTH-1:0]   gpio_enable,
    output logic [GPIO_WIDTH-1:0]   gpio_int,
    output logic                    comb_int
);

    // APB register address map (word-aligned paddr[7:2])
    typedef enum logic [5:0] {
        ADDR_GPIO_IN       = 6'h00, // 0x00: GPIO Input Data (RO)
        ADDR_GPIO_OUT      = 6'h01, // 0x04: GPIO Output Data (RW)
        ADDR_GPIO_OE       = 6'h02, // 0x08: GPIO Output Enable (RW)
        ADDR_GPIO_INT_EN   = 6'h03, // 0x0C: GPIO Interrupt Enable (RW)
        ADDR_GPIO_INT_TYPE = 6'h04, // 0x10: GPIO Interrupt Type (0: Level, 1: Edge) (RW)
        ADDR_GPIO_INT_POL  = 6'h05, // 0x14: GPIO Interrupt Polarity (0: Low/Falling, 1: High/Rising) (RW)
        ADDR_GPIO_INT_STAT = 6'h06  // 0x18: GPIO Interrupt State (RO)
    } apb_reg_addr_e;

    // APB static responses (zero wait states, error-free)
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    // APB control signals
    logic apb_write_en;
    logic apb_read_en;

    assign apb_write_en = psel && penable && pwrite;
    assign apb_read_en  = psel && !pwrite;

    // Two-stage input synchronizer and previous-state register for edge detection
    logic [GPIO_WIDTH-1:0] gpio_in_sync1;
    logic [GPIO_WIDTH-1:0] gpio_in_sync2;
    logic [GPIO_WIDTH-1:0] gpio_in_prev;

    always_ff @(posedge pclk or negedge preset_n) begin
        if (!preset_n) begin
            gpio_in_sync1 <= {GPIO_WIDTH{1'b0}};
            gpio_in_sync2 <= {GPIO_WIDTH{1'b0}};
            gpio_in_prev  <= {GPIO_WIDTH{1'b0}};
        end else begin
            gpio_in_sync1 <= gpio_in;
            gpio_in_sync2 <= gpio_in_sync1;
            gpio_in_prev  <= gpio_in_sync2;
        end
    end

    // Programmable GPIO registers
    logic [GPIO_WIDTH-1:0] reg_out;
    logic [GPIO_WIDTH-1:0] reg_oe;
    logic [GPIO_WIDTH-1:0] reg_int_en;
    logic [GPIO_WIDTH-1:0] reg_int_type;
    logic [GPIO_WIDTH-1:0] reg_int_pol;

    always_ff @(posedge pclk or negedge preset_n) begin
        if (!preset_n) begin
            reg_out      <= {GPIO_WIDTH{1'b0}};
            reg_oe       <= {GPIO_WIDTH{1'b0}};
            reg_int_en   <= {GPIO_WIDTH{1'b0}};
            reg_int_type <= {GPIO_WIDTH{1'b0}};
            reg_int_pol  <= {GPIO_WIDTH{1'b0}};
        end else if (apb_write_en) begin
            case (paddr)
                ADDR_GPIO_OUT:      reg_out      <= pwdata[GPIO_WIDTH-1:0];
                ADDR_GPIO_OE:       reg_oe       <= pwdata[GPIO_WIDTH-1:0];
                ADDR_GPIO_INT_EN:   reg_int_en   <= pwdata[GPIO_WIDTH-1:0];
                ADDR_GPIO_INT_TYPE: reg_int_type <= pwdata[GPIO_WIDTH-1:0];
                ADDR_GPIO_INT_POL:  reg_int_pol  <= pwdata[GPIO_WIDTH-1:0];
                default: ;
            endcase
        end
    end

    // GPIO output and direction control
    assign gpio_out    = reg_out;
    assign gpio_enable = reg_oe;

    // Interrupt generation logic (level/edge sensitivity and active-high/low polarity)
    logic [GPIO_WIDTH-1:0] rising_edge;
    logic [GPIO_WIDTH-1:0] falling_edge;
    logic [GPIO_WIDTH-1:0] edge_int;
    logic [GPIO_WIDTH-1:0] level_int;
    logic [GPIO_WIDTH-1:0] raw_int;

    always_comb begin
        rising_edge  = gpio_in_sync2 & ~gpio_in_prev;
        falling_edge = ~gpio_in_sync2 & gpio_in_prev;
        edge_int     = (reg_int_pol & rising_edge) | (~reg_int_pol & falling_edge);
        level_int    = (reg_int_pol & gpio_in_sync2) | (~reg_int_pol & ~gpio_in_sync2);
        raw_int      = (reg_int_type & edge_int) | (~reg_int_type & level_int);
        gpio_int     = reg_int_en & raw_int;
        comb_int     = |gpio_int;
    end

    // APB read data multiplexer
    always_comb begin
        prdata = 32'h0000_0000;
        if (apb_read_en) begin
            case (paddr)
                ADDR_GPIO_IN:       prdata[GPIO_WIDTH-1:0] = gpio_in_sync2;
                ADDR_GPIO_OUT:      prdata[GPIO_WIDTH-1:0] = reg_out;
                ADDR_GPIO_OE:       prdata[GPIO_WIDTH-1:0] = reg_oe;
                ADDR_GPIO_INT_EN:   prdata[GPIO_WIDTH-1:0] = reg_int_en;
                ADDR_GPIO_INT_TYPE: prdata[GPIO_WIDTH-1:0] = reg_int_type;
                ADDR_GPIO_INT_POL:  prdata[GPIO_WIDTH-1:0] = reg_int_pol;
                ADDR_GPIO_INT_STAT: prdata[GPIO_WIDTH-1:0] = gpio_int;
                default:            prdata                 = 32'h0000_0000;
            endcase
        end
    end

endmodule
