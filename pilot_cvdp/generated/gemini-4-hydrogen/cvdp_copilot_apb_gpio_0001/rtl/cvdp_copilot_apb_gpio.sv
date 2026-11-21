module cvdp_copilot_apb_gpio #(
    parameter int GPIO_WIDTH = 8
) (
    // Clock and Reset
    input  logic                    pclk,
    input  logic                    preset_n,

    // APB Interface
    input  logic                    psel,
    input  logic [7:2]              paddr,
    input  logic                    penable,
    input  logic                    pwrite,
    input  logic [31:0]             pwdata,
    output logic [31:0]             prdata,
    output logic                    pready,
    output logic                    pslverr,

    // GPIO Interface
    input  logic [GPIO_WIDTH-1:0]   gpio_in,
    output logic [GPIO_WIDTH-1:0]   gpio_out,
    output logic [GPIO_WIDTH-1:0]   gpio_enable,

    // Interrupt Interface
    output logic [GPIO_WIDTH-1:0]   gpio_int,
    output logic                    comb_int
);

    // APB Word-Aligned Register Address Map (paddr[7:2])
    typedef enum logic [5:0] {
        ADDR_IN        = 6'h00, // 0x00: GPIO Input Data (Read-only)
        ADDR_OUT       = 6'h01, // 0x04: GPIO Output Data (Read/Write)
        ADDR_OE        = 6'h02, // 0x08: GPIO Output Enable (Read/Write)
        ADDR_INT_EN    = 6'h03, // 0x0C: GPIO Interrupt Enable (Read/Write)
        ADDR_INT_TYPE  = 6'h04, // 0x10: GPIO Interrupt Type: 1=Edge, 0=Level (Read/Write)
        ADDR_INT_POL   = 6'h05, // 0x14: GPIO Interrupt Polarity: 1=Active-High/Rising, 0=Active-Low/Falling (Read/Write)
        ADDR_INT_STATE = 6'h06  // 0x18: GPIO Interrupt State (Read-only)
    } apb_addr_t;

    // Internal Configuration and Control Registers
    logic [GPIO_WIDTH-1:0] reg_out;
    logic [GPIO_WIDTH-1:0] reg_oe;
    logic [GPIO_WIDTH-1:0] reg_int_en;
    logic [GPIO_WIDTH-1:0] reg_int_type;
    logic [GPIO_WIDTH-1:0] reg_int_pol;

    // Two-Stage Input Synchronizer and Edge-Detection History Register
    logic [GPIO_WIDTH-1:0] gpio_in_sync1;
    logic [GPIO_WIDTH-1:0] gpio_in_sync2;
    logic [GPIO_WIDTH-1:0] gpio_in_prev;

    // Interrupt Detection Signals
    logic [GPIO_WIDTH-1:0] rising_edge;
    logic [GPIO_WIDTH-1:0] falling_edge;
    logic [GPIO_WIDTH-1:0] high_level;
    logic [GPIO_WIDTH-1:0] low_level;
    logic [GPIO_WIDTH-1:0] edge_int;
    logic [GPIO_WIDTH-1:0] level_int;
    logic [GPIO_WIDTH-1:0] raw_int;
    logic [GPIO_WIDTH-1:0] reg_int_state;

    // APB Ready and Error Responses (Zero Wait-State, Error-Free)
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    // GPIO Output and Direction Control
    assign gpio_out    = reg_out;
    assign gpio_enable = reg_oe;

    // Two-Stage Flip-Flop Synchronizer and Previous-State Capture for Edge Detection
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

    // APB Write Logic (ACCESS Phase: psel && penable && pwrite)
    always_ff @(posedge pclk or negedge preset_n) begin
        if (!preset_n) begin
            reg_out      <= '0;
            reg_oe       <= '0;
            reg_int_en   <= '0;
            reg_int_type <= '0;
            reg_int_pol  <= '0;
        end else if (psel && penable && pwrite) begin
            case (paddr)
                ADDR_OUT:      reg_out      <= pwdata[GPIO_WIDTH-1:0];
                ADDR_OE:       reg_oe       <= pwdata[GPIO_WIDTH-1:0];
                ADDR_INT_EN:   reg_int_en   <= pwdata[GPIO_WIDTH-1:0];
                ADDR_INT_TYPE: reg_int_type <= pwdata[GPIO_WIDTH-1:0];
                ADDR_INT_POL:  reg_int_pol  <= pwdata[GPIO_WIDTH-1:0];
                default: ; // Read-only or undefined addresses: no effect
            endcase
        end
    end

    // Bitwise Interrupt Generation Logic
    assign rising_edge   =  gpio_in_sync2 & ~gpio_in_prev;
    assign falling_edge  = ~gpio_in_sync2 &  gpio_in_prev;
    assign high_level    =  gpio_in_sync2;
    assign low_level     = ~gpio_in_sync2;

    assign edge_int      = (reg_int_pol  & rising_edge) | (~reg_int_pol  & falling_edge);
    assign level_int     = (reg_int_pol  & high_level)  | (~reg_int_pol  & low_level);
    assign raw_int       = (reg_int_type & edge_int)    | (~reg_int_type & level_int);

    assign reg_int_state = raw_int & reg_int_en;
    assign gpio_int      = reg_int_state;
    assign comb_int      = |gpio_int;

    // APB Read Logic
    always_comb begin
        prdata = 32'b0;
        if (preset_n && psel && !pwrite) begin
            case (paddr)
                ADDR_IN:        prdata[GPIO_WIDTH-1:0] = gpio_in_sync2;
                ADDR_OUT:       prdata[GPIO_WIDTH-1:0] = reg_out;
                ADDR_OE:        prdata[GPIO_WIDTH-1:0] = reg_oe;
                ADDR_INT_EN:    prdata[GPIO_WIDTH-1:0] = reg_int_en;
                ADDR_INT_TYPE:  prdata[GPIO_WIDTH-1:0] = reg_int_type;
                ADDR_INT_POL:   prdata[GPIO_WIDTH-1:0] = reg_int_pol;
                ADDR_INT_STATE: prdata[GPIO_WIDTH-1:0] = reg_int_state;
                default:        prdata                 = 32'b0;
            endcase
        end
    end

endmodule
