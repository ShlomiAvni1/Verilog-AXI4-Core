// -----------------------------------------------------------------------------
// Module: axi_master
// -----------------------------------------------------------------------------
// Description:
// AXI4 Master Interface Controller.
//
// This module implements a master interface compliant with the AXI4
// specification (configured for single-beat transactions). It provides a 
// simplified user interface to initiate Write and Read transactions, 
// abstracting the complexity of the AXI handshake protocol.
//
// Architecture:
// The design utilizes two independent Finite State Machines (FSMs) to manage
// the Write and Read channels. Simple arbitration logic ensures safe access
// to the bus when simultaneous requests occur.
// -----------------------------------------------------------------------------

module axi_master #(
    parameter C_M_AXI_DATA_WIDTH = 32,
    parameter C_M_AXI_ADDR_WIDTH = 32
) (
    // Global Signals
    input  wire                          aclk,
    input  wire                          aresetn,

    // --- User Interface (Northbound) ---
    // Inputs from the "user" (e.g., a CPU or a Testbench)
    input  wire                          start_write, // Initiates a write transaction
    input  wire                          start_read,  // Initiates a read transaction
    input  wire [C_M_AXI_ADDR_WIDTH-1:0] user_addr,   // Target address
    input  wire [C_M_AXI_DATA_WIDTH-1:0] user_wdata,  // Write data
    
    // Outputs to the "user"
    output wire                          user_write_done, // Asserted when write completes
    output wire                          user_read_done,  // Asserted when read completes
    output wire [C_M_AXI_DATA_WIDTH-1:0] user_rdata,      // Read data output
    output wire                          master_busy,     // Active during ongoing transaction

    // --- AXI Interface (Southbound) ---
    // Write Address Channel
    output wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [2:0]                    m_axi_awprot,
    output wire                          m_axi_awvalid,
    input  wire                          m_axi_awready,

    // Write Data Channel
    output wire [C_M_AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output wire                          m_axi_wvalid,
    input  wire                          m_axi_wready,

    // Write Response Channel
    input  wire [1:0]                    m_axi_bresp,
    input  wire                          m_axi_bvalid,
    output wire                          m_axi_bready,

    // Read Address Channel
    output wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [2:0]                    m_axi_arprot,
    output wire                          m_axi_arvalid,
    input  wire                          m_axi_arready,

    // Read Data Channel
    input  wire [C_M_AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]                    m_axi_rresp,
    input  wire                          m_axi_rvalid,
    output wire                          m_axi_rready
);

    // -------------------------------------------------------------------------
    // Signal Declarations
    // -------------------------------------------------------------------------

    // AXI Output Registers
    reg [C_M_AXI_ADDR_WIDTH-1:0] axi_awaddr_reg;
    reg                          axi_awvalid_reg;
    reg [C_M_AXI_DATA_WIDTH-1:0] axi_wdata_reg;
    reg                          axi_wvalid_reg;
    reg                          axi_bready_reg;
    reg [C_M_AXI_ADDR_WIDTH-1:0] axi_araddr_reg;
    reg                          axi_arvalid_reg;
    reg                          axi_rready_reg;

    // User Interface Output Registers
    reg                          user_write_done_reg;
    reg                          user_read_done_reg;
    reg [C_M_AXI_DATA_WIDTH-1:0] user_rdata_reg;
    reg                          master_busy_reg;

    // Transaction Latches
    reg [C_M_AXI_ADDR_WIDTH-1:0] internal_addr;
    reg [C_M_AXI_DATA_WIDTH-1:0] internal_wdata;

    // -------------------------------------------------------------------------
    // Write Channel Finite State Machine
    // -------------------------------------------------------------------------
    
    localparam FSM_W_IDLE   = 2'b00;
    localparam FSM_W_ADDR   = 2'b01;
    localparam FSM_W_DATA   = 2'b10;
    localparam FSM_W_RESP   = 2'b11;
    
    reg [1:0] write_fsm_state;

    always @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            write_fsm_state     <= FSM_W_IDLE;
            axi_awvalid_reg     <= 1'b0;
            axi_wvalid_reg      <= 1'b0;
            axi_bready_reg      <= 1'b0;
            user_write_done_reg <= 1'b0;
            master_busy_reg     <= 1'b0;
            internal_addr       <= 0;
            internal_wdata      <= 0;
        end else begin
            // Pulse generation for user done signal
            if (user_write_done_reg) begin
                user_write_done_reg <= 1'b0;
            end

            case (write_fsm_state)
                
                // IDLE: Monitor for start command
                FSM_W_IDLE: begin
                    axi_awvalid_reg <= 1'b0;
                    axi_wvalid_reg  <= 1'b0;
                    axi_bready_reg  <= 1'b0;
                    master_busy_reg <= 1'b0;

                    // Arbitration: Write takes priority if both asserted
                    if (start_write && ~master_busy_reg) begin
                        master_busy_reg     <= 1'b1;
                        internal_addr       <= user_addr;
                        internal_wdata      <= user_wdata;
                        axi_awaddr_reg      <= user_addr;
                        axi_wdata_reg       <= user_wdata;
                        axi_awvalid_reg     <= 1'b1;
                        write_fsm_state     <= FSM_W_ADDR;
                    end
                end
                
                // ADDR: Assert AWVALID and wait for AWREADY
                FSM_W_ADDR: begin
                    if (m_axi_awready && axi_awvalid_reg) begin
                        axi_awvalid_reg <= 1'b0;
                        axi_wvalid_reg  <= 1'b1;
                        write_fsm_state <= FSM_W_DATA;
                    end
                end
                
                // DATA: Assert WVALID and wait for WREADY
                FSM_W_DATA: begin
                    if (m_axi_wready && axi_wvalid_reg) begin
                        axi_wvalid_reg  <= 1'b0;
                        axi_bready_reg  <= 1'b1;
                        write_fsm_state <= FSM_W_RESP;
                    end
                end
                
                // RESP: Wait for BVALID from slave
                FSM_W_RESP: begin
                    if (m_axi_bvalid && axi_bready_reg) begin
                        axi_bready_reg      <= 1'b0;
                        user_write_done_reg <= 1'b1;
                        master_busy_reg     <= 1'b0;
                        write_fsm_state     <= FSM_W_IDLE;
                    end
                end
                
            endcase
        end
    end
    
    // -------------------------------------------------------------------------
    // Read Channel Finite State Machine
    // -------------------------------------------------------------------------
    
    localparam FSM_R_IDLE   = 2'b00;
    localparam FSM_R_ADDR   = 2'b01;
    localparam FSM_R_DATA   = 2'b10;
    
    reg [1:0] read_fsm_state;

    always @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            read_fsm_state     <= FSM_R_IDLE;
            axi_arvalid_reg    <= 1'b0;
            axi_rready_reg     <= 1'b0;
            user_read_done_reg <= 1'b0;
        end else begin
            if (user_read_done_reg) begin
                user_read_done_reg <= 1'b0;
            end

            case (read_fsm_state)
                
                // IDLE: Monitor for start command
                FSM_R_IDLE: begin
                    axi_arvalid_reg <= 1'b0;
                    axi_rready_reg  <= 1'b0;
                    
                    if (start_read && ~master_busy_reg) begin
                        master_busy_reg <= 1'b1;
                        axi_araddr_reg  <= user_addr;
                        axi_arvalid_reg <= 1'b1;
                        read_fsm_state  <= FSM_R_ADDR;
                    end
                end
                
                // ADDR: Assert ARVALID and wait for ARREADY
                FSM_R_ADDR: begin
                    if (m_axi_arready && axi_arvalid_reg) begin
                        axi_arvalid_reg <= 1'b0;
                        axi_rready_reg  <= 1'b1;
                        read_fsm_state  <= FSM_R_DATA;
                    end
                end
                
                // DATA: Wait for RVALID from slave
                FSM_R_DATA: begin
                    if (m_axi_rvalid && axi_rready_reg) begin
                        axi_rready_reg     <= 1'b0;
                        user_rdata_reg     <= m_axi_rdata;
                        user_read_done_reg <= 1'b1;
                        master_busy_reg    <= 1'b0;
                        read_fsm_state     <= FSM_R_IDLE;
                    end
                end
                
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Output Signal Assignments
    // -------------------------------------------------------------------------
    
    // User Interface
    assign user_write_done = user_write_done_reg;
    assign user_read_done  = user_read_done_reg;
    assign user_rdata      = user_rdata_reg;
    assign master_busy     = master_busy_reg;
    
    // Write Address
    assign m_axi_awaddr  = axi_awaddr_reg;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awvalid = axi_awvalid_reg;
    
    // Write Data
    assign m_axi_wdata   = axi_wdata_reg;
    assign m_axi_wstrb   = 4'hF;
    assign m_axi_wvalid  = axi_wvalid_reg;
    
    // Write Response
    assign m_axi_bready  = axi_bready_reg;
    
    // Read Address
    assign m_axi_araddr  = axi_araddr_reg;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arvalid = axi_arvalid_reg;
    
    // Read Data
    assign m_axi_rready  = axi_rready_reg;

endmodule
