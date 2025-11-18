// -----------------------------------------------------------------------------
// Module: axi_slave
// -----------------------------------------------------------------------------
// Description:
// AXI4 Slave Interface with 4-Register Memory Map.
//
// This module implements an AXI4 slave that maps to a contiguous block
// of four 32-bit registers. It supports standard read and write transactions
// with pipelined read response logic for timing optimization.
//
// Address Map:
// Offset 0x00: Register 0
// Offset 0x04: Register 1
// Offset 0x08: Register 2
// Offset 0x0C: Register 3
// -----------------------------------------------------------------------------

module axi_slave #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 32
) (
    // Global Signals
    input  wire                          aclk,
    input  wire                          aresetn, // Active-low reset

    // Write Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [2:0]                    s_axi_awprot,
    input  wire                          s_axi_awvalid,
    output wire                          s_axi_awready,

    // Write Data Channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output wire                          s_axi_wready,

    // Write Response Channel
    output wire [1:0]                    s_axi_bresp,
    output wire                          s_axi_bvalid,
    input  wire                          s_axi_bready,

    // Read Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [2:0]                    s_axi_arprot,
    input  wire                          s_axi_arvalid,
    output wire                          s_axi_arready,

    // Read Data Channel
    output wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]                    s_axi_rresp,
    output wire                          s_axi_rvalid,
    input  wire                          s_axi_rready
);

    // -------------------------------------------------------------------------
    // Signal Declarations
    // -------------------------------------------------------------------------
    
    // AXI Output Registers
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr_reg;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr_reg;
    reg axi_awready_reg;
    reg axi_wready_reg;
    reg axi_arready_reg;
    reg [1:0] axi_bresp_reg;
    reg       axi_bvalid_reg;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata_reg;
    reg [1:0] axi_rresp_reg;
    reg       axi_rvalid_reg;
    
    // Pipeline Control Register
    // Indicates that an address handshake occurred in the previous cycle.
    reg       ar_handshake_occurred_reg; 

    // -------------------------------------------------------------------------
    // Register Space
    // -------------------------------------------------------------------------
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg0;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg1;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg2;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg3;

    // Internal multiplexed read data
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg_rdata;


    // -------------------------------------------------------------------------
    // Output Assignments
    // -------------------------------------------------------------------------
    assign s_axi_awready = axi_awready_reg;
    assign s_axi_wready  = axi_wready_reg;
    assign s_axi_bresp   = axi_bresp_reg;
    assign s_axi_bvalid  = axi_bvalid_reg;
    assign s_axi_arready = axi_arready_reg;
    assign s_axi_rdata   = axi_rdata_reg;
    assign s_axi_rresp   = axi_rresp_reg;
    assign s_axi_rvalid  = axi_rvalid_reg;
    
    // -------------------------------------------------------------------------
    // Write Address (AW) Channel Logic
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_awready_reg <= 1'b0;
            axi_awaddr_reg  <= 0;
        // Address Handshake
        end else if (s_axi_awvalid && axi_awready_reg) begin
            axi_awready_reg <= 1'b0;
            axi_awaddr_reg  <= s_axi_awaddr;
        // Ready generation logic
        end else if (~axi_wready_reg && ~axi_bvalid_reg) begin
            axi_awready_reg <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Write Data (W) Channel Logic
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_wready_reg <= 1'b0;
        // Wait for address before asserting ready for data
        end else if (~axi_awready_reg && ~axi_wready_reg && ~axi_bvalid_reg) begin
            axi_wready_reg <= 1'b1;
        // Data Handshake
        end else if (s_axi_wvalid && axi_wready_reg) begin
            axi_wready_reg <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Write Implementation
    // -------------------------------------------------------------------------
    wire [1:0] sel_reg_write = axi_awaddr_reg[3:2];
    
    always @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            slv_reg0 <= 0;
            slv_reg1 <= 0;
            slv_reg2 <= 0;
            slv_reg3 <= 0;
        end else if (s_axi_wvalid && axi_wready_reg) begin
            case (sel_reg_write)
                2'b00:  slv_reg0 <= s_axi_wdata;
                2'b01:  slv_reg1 <= s_axi_wdata;
                2'b10:  slv_reg2 <= s_axi_wdata;
                2'b11:  slv_reg3 <= s_axi_wdata;
                default: begin
                    // Maintain current values
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Write Response (B) Channel Logic
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_bvalid_reg <= 1'b0;
            axi_bresp_reg  <= 2'b0; // OKAY
        // Response Valid generation
        end else if (s_axi_wvalid && axi_wready_reg) begin 
            axi_bvalid_reg <= 1'b1;
            axi_bresp_reg  <= 2'b0; 
        // Response Handshake
        end else if (s_axi_bready && axi_bvalid_reg) begin
            axi_bvalid_reg <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Read Address (AR) Channel Logic
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_arready_reg           <= 1'b0;
            axi_araddr_reg            <= 32'b0;
            ar_handshake_occurred_reg <= 1'b0;
        // Address Handshake
        end else if (s_axi_arvalid && axi_arready_reg) begin
            axi_arready_reg           <= 1'b0;
            axi_araddr_reg            <= s_axi_araddr;
            ar_handshake_occurred_reg <= 1'b1; // Assert pipeline flag
        // Completion
        end else if (s_axi_rready && axi_rvalid_reg) begin 
            axi_arready_reg           <= 1'b1;
            ar_handshake_occurred_reg <= 1'b0;
        // Clear flag if set but not consumed
        end else if (ar_handshake_occurred_reg) begin
            ar_handshake_occurred_reg <= 1'b0;
        // Ready generation
        end else if (~axi_arready_reg && ~axi_rvalid_reg) begin
             axi_arready_reg <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Read Data Multiplexer
    // -------------------------------------------------------------------------
    wire [1:0] sel_reg_read = axi_araddr_reg[3:2];
    
    always @(*) begin
        case (sel_reg_read)
            2'b00:   slv_reg_rdata = slv_reg0;
            2'b01:   slv_reg_rdata = slv_reg1;
            2'b10:   slv_reg_rdata = slv_reg2;
            2'b11:   slv_reg_rdata = slv_reg3;
            default: slv_reg_rdata = 32'hDEADBEEF; // Error indication
        endcase
    end
    
    // -------------------------------------------------------------------------
    // Read Data (R) Channel Logic
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_rvalid_reg <= 1'b0;
            axi_rresp_reg  <= 2'b0;
            axi_rdata_reg  <= 32'b0;
        // Pipeline stage: Data is valid one cycle after address handshake
        end else if (ar_handshake_occurred_reg && ~axi_rvalid_reg) begin
            axi_rvalid_reg <= 1'b1;
            axi_rresp_reg  <= 2'b0; // OKAY
            axi_rdata_reg  <= slv_reg_rdata;
        // Data Handshake
        end else if (s_axi_rready && axi_rvalid_reg) begin
            axi_rvalid_reg <= 1'b0;
        end
    end

endmodule