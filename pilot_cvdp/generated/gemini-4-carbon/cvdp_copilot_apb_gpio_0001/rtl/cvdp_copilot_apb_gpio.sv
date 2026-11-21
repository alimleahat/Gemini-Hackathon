module cvdp_copilot_apb_gpio #(
    parameter int GPIO_WIDTH = 8
) (
    // APB Interface
    input  logic                  pclk,
    input  logic                  preset_n,
    input  logic                  psel,
    input  logic [7:2]            paddr,
    input  logic                  penable,
    input  logic                  pwrite,
    input  logic [31:0]           pwdata,
    output logic [31:0]           prdata,
    output logic                  pready,
    output logic                  pslverr,

    // GPIO Interface
    input  logic [GPIO_WIDTH-1:0] gpio_in,
    output logic [GPIO_WIDTH-1:0] gpio_out,
    output logic [GPIO_WIDTH-1:0] gpio_enable,

    // Interrupt Interface
    output logic [GPIO_WIDTH-1:0] gpio_int,
    output logic                  comb_int
);

    // Effective APB data width for register transfers
    localparam int DATA_BITS = (GPIO_WIDTH < 32) ? GPIO_WIDTH : 32;

    // Register Map Word Offsets (paddr[7:2])
    typedef enum logic [5:0] {
        ADDR_GPIO_IN       = 6'h00, // 0x00: GPIO Input Data (Read-only)
        ADDR_GPIO_OUT      = 6'h01, // 0x04: GPIO Output Data (R/W)
        ADDR_GPIO_OE       = 6'h02, // 0x08: GPIO Output Enable (R/W)
        ADDR_GPIO_INT_EN   = 6'h03, // 0x0C: GPIO Interrupt Enable (R/W)
        ADDR_GPIO_INT_TYPE = 6'h04, // 0x10: GPIO Interrupt Type (0: Level, 1: Edge) (R/W)
        ADDR_GPIO_INT_POL  = 6'h05, // 0x14: GPIO Interrupt Polarity (0: Low/Falling, 1: High/Rising) (R/W)
        ADDR_GPIO_INT_STAT = 6'h06  // 0x18: GPIO Interrupt State (Read-only)
    } gpio_reg_addr_e;

    // Synchronizer and edge-detection registers
    logic [GPIO_WIDTH-1:0] gpio_in_sync1;
    logic [GPIO_WIDTH-1:0] gpio_in_sync2;
    logic [GPIO_WIDTH-1:0] gpio_in_prev;

    // Configuration and control registers
    logic [GPIO_WIDTH-1:0] reg_out;
    logic [GPIO_WIDTH-1:0] reg_oe;
    logic [GPIO_WIDTH-1:0] reg_int_en;
    logic [GPIO_WIDTH-1:0] reg_int_type;
    logic [GPIO_WIDTH-1:0] reg_int_pol;

    // Interrupt detection signals
    logic [GPIO_WIDTH-1:0] rising_edge;
    logic [GPIO_WIDTH-1:0] falling_edge;
    logic [GPIO_WIDTH-1:0] edge_int;
    logic [GPIO_WIDTH-1:0] level_int;
    logic [GPIO_WIDTH-1:0] raw_int;

    // APB transaction qualification
    logic apb_write;
    logic apb_read;

    assign apb_write = psel && penable && pwrite;
    assign apb_read  = psel && !pwrite;

    // Zero-wait-state, error-free APB responses
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    // Two-stage input synchronizer and history flop for edge detection
    always_ff @(posedge pclk or negedge preset_n) begin
        if (!preset_n) begin
            gpio_in_sync1 <= '0;
            gpio_in_sync2 <= '0;
            gpio_in_prev  <= '0;
        end else begin
            gpio_in_sync1 <= gpio_in;
            gpio_in_sync2 <= gpio_in_sync1;
            gpio_in_prev  <= gpio_in_sync2;
        end
    end

    // APB Write Logic
    always_ff @(posedge pclk or negedge preset_n) begin
        if (!preset_n) begin
            reg_out      <= '0;
            reg_oe       <= '0;
            reg_int_en   <= '0;
            reg_int_type <= '0;
            reg_int_pol  <= '0;
        end else if (apb_write) begin
            case (paddr)
                ADDR_GPIO_OUT:      reg_out[DATA_BITS-1:0]      <= pwdata[DATA_BITS-1:0];
                ADDR_GPIO_OE:       reg_oe[DATA_BITS-1:0]       <= pwdata[DATA_BITS-1:0];
                ADDR_GPIO_INT_EN:   reg_int_en[DATA_BITS-1:0]   <= pwdata[DATA_BITS-1:0];
                ADDR_GPIO_INT_TYPE: reg_int_type[DATA_BITS-1:0] <= pwdata[DATA_BITS-1:0];
                ADDR_GPIO_INT_POL:  reg_int_pol[DATA_BITS-1:0]  <= pwdata[DATA_BITS-1:0];
                default: ; // Read-only and undefined addresses are ignored on write
            endcase
        end
    end

    // GPIO Output and Direction Assignments
    assign gpio_out    = reg_out;
    assign gpio_enable = reg_oe;

    // Interrupt Generation Logic
    always_comb begin
        rising_edge  = gpio_in_sync2 & ~gpio_in_prev;
        falling_edge = ~gpio_in_sync2 & gpio_in_prev;

        // Polarity selection: 1 = active-high / rising-edge, 0 = active-low / falling-edge
        edge_int     = (reg_int_pol & rising_edge) | (~reg_int_pol & falling_edge);
        level_int    = (reg_int_pol & gpio_in_sync2) | (~reg_int_pol & ~gpio_in_sync2);

        // Sensitivity selection: 1 = edge-sensitive, 0 = level-sensitive
        raw_int      = (reg_int_type & edge_int) | (~reg_int_type & level_int);

        // Mask with interrupt enable
        gpio_int     = reg_int_en & raw_int;
        comb_int     = |gpio_int;
    end

    // APB Read Logic
    always_comb begin
        prdata = 32'd0;
        if (apb_read) begin
            case (paddr)
                ADDR_GPIO_IN:       prdata[DATA_BITS-1:0] = gpio_in_sync2[DATA_BITS-1:0];
                ADDR_GPIO_OUT:      prdata[DATA_BITS-1:0] = reg_out[DATA_BITS-1:0];
                ADDR_GPIO_OE:       prdata[DATA_BITS-1:0] = reg_oe[DATA_BITS-1:0];
                ADDR_GPIO_INT_EN:   prdata[DATA_BITS-1:0] = reg_int_en[DATA_BITS-1:0];
                ADDR_GPIO_INT_TYPE: prdata[DATA_BITS-1:0] = reg_int_type[DATA_BITS-1:0];
                ADDR_GPIO_INT_POL:  prdata[DATA_BITS-1:0] = reg_int_pol[DATA_BITS-1:0];
                ADDR_GPIO_INT_STAT: prdata[DATA_BITS-1:0] = gpio_int[DATA_BITS-1:0];
                default:            prdata                = 32'd0;
            endcase
        end
    end

endmodule
