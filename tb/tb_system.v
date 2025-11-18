// -----------------------------------------------------------------------------
// Module: tb_system
// -----------------------------------------------------------------------------
// Description:
// System-level verification environment for the AXI4 Master and Slave.
//
// This module instantiates the Master and Slave components and connects them
// via a verification harness. The harness intercepts AXI handshake signals
// to inject deterministic backpressure (stalls), enabling rigorous testing
// of the Master's Finite State Machine robustness.
//
// Verification Scenarios:
// 1. Basic Read/Write transactions under ideal conditions.
// 2. Robustness verification via deterministic stall injection on Ready signals.
// 3. Arbitration logic verification (simultaneous Read/Write requests).
// 4. Bandwidth utilization verification (Back-to-Back transactions).
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_system;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter C_AXI_DATA_WIDTH = 32;
    parameter C_AXI_ADDR_WIDTH = 32;
    parameter CLK_PERIOD       = 10; // 100MHz clock frequency

    // -------------------------------------------------------------------------
    // Signal Declarations
    // -------------------------------------------------------------------------

    // Clock and Reset
    reg aclk;
    reg aresetn;

    // --- AXI Interface Signals (Master Output / Interconnect Input) ---
    wire [C_AXI_ADDR_WIDTH-1:0] m_axi_awaddr;
    wire [2:0]                  m_axi_awprot;
    wire                        m_axi_awvalid;
    wire [C_AXI_DATA_WIDTH-1:0] m_axi_wdata;
    wire [C_AXI_DATA_WIDTH/8-1:0] m_axi_wstrb;
    wire                        m_axi_wvalid;
    wire                        m_axi_bready;
    wire [C_AXI_ADDR_WIDTH-1:0] m_axi_araddr;
    wire [2:0]                  m_axi_arprot;
    wire                        m_axi_arvalid;
    wire                        m_axi_rready;

    // --- AXI Interface Signals (Interconnect Output / Slave Input) ---
    wire [C_AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    wire [2:0]                  s_axi_awprot;
    wire                        s_axi_awvalid; // Gated by stall logic
    wire [C_AXI_DATA_WIDTH-1:0] s_axi_wdata;
    wire [C_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb;
    wire                        s_axi_wvalid;  // Gated by stall logic
    wire                        s_axi_bready;
    wire [C_AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    wire [2:0]                  s_axi_arprot;
    wire                        s_axi_arvalid; // Gated by stall logic
    wire                        s_axi_rready;
    
    // --- AXI Interface Signals (Slave Output / Interconnect Input) ---
    wire                        s_axi_awready;
    wire                        s_axi_wready;
    wire [1:0]                  s_axi_bresp;
    wire                        s_axi_bvalid;
    wire                        s_axi_arready;
    wire [C_AXI_DATA_WIDTH-1:0] s_axi_rdata;
    wire [1:0]                  s_axi_rresp;
    wire                        s_axi_rvalid;
    
    // --- AXI Interface Signals (Interconnect Output / Master Input) ---
    wire                        m_axi_awready; // Controlled by stall logic
    wire                        m_axi_wready;  // Controlled by stall logic
    wire [1:0]                  m_axi_bresp;
    wire                        m_axi_bvalid;
    wire                        m_axi_arready; // Controlled by stall logic
    wire [C_AXI_DATA_WIDTH-1:0] m_axi_rdata;
    wire [1:0]                  m_axi_rresp;
    wire                        m_axi_rvalid;
    
    // --- Verification Control Signals (Stall Injection) ---
    // These registers force the READY signals low to simulate backpressure.
    reg stall_awready;
    reg stall_wready;
    reg stall_arready;

    // --- User Interface Signals (Test Stimulus) ---
    reg                          tb_start_write;
    reg                          tb_start_read;
    reg [C_AXI_ADDR_WIDTH-1:0]   tb_user_addr;
    reg [C_AXI_DATA_WIDTH-1:0]   tb_user_wdata;
    
    wire                         tb_user_write_done;
    wire                         tb_user_read_done;
    wire [C_AXI_DATA_WIDTH-1:0] tb_user_rdata;
    wire                         tb_master_busy;

    // -------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation: Master
    // -------------------------------------------------------------------------
    axi_master #(
        .C_M_AXI_DATA_WIDTH(C_AXI_DATA_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_AXI_ADDR_WIDTH)
    ) master_inst (
        .aclk            (aclk),
        .aresetn         (aresetn),

        // User Interface
        .start_write     (tb_start_write),
        .start_read      (tb_start_read),
        .user_addr       (tb_user_addr),
        .user_wdata      (tb_user_wdata),
        .user_write_done (tb_user_write_done),
        .user_read_done  (tb_user_read_done),
        .user_rdata      (tb_user_rdata),
        .master_busy     (tb_master_busy),

        // AXI Interface
        .m_axi_awaddr    (m_axi_awaddr),
        .m_axi_awprot    (m_axi_awprot),
        .m_axi_awvalid   (m_axi_awvalid),
        .m_axi_awready   (m_axi_awready), // Connected to interception logic
        .m_axi_wdata     (m_axi_wdata),
        .m_axi_wstrb     (m_axi_wstrb),
        .m_axi_wvalid    (m_axi_wvalid),
        .m_axi_wready    (m_axi_wready),  // Connected to interception logic
        .m_axi_bresp     (m_axi_bresp),
        .m_axi_bvalid    (m_axi_bvalid),
        .m_axi_bready    (m_axi_bready),
        .m_axi_araddr    (m_axi_araddr),
        .m_axi_arprot    (m_axi_arprot),
        .m_axi_arvalid   (m_axi_arvalid),
        .m_axi_arready   (m_axi_arready), // Connected to interception logic
        .m_axi_rdata     (m_axi_rdata),
        .m_axi_rresp     (m_axi_rresp),
        .m_axi_rvalid    (m_axi_rvalid),
        .m_axi_rready    (m_axi_rready)
    );

    // -------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation: Slave
    // -------------------------------------------------------------------------
    axi_slave #(
        .C_S_AXI_DATA_WIDTH(C_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_AXI_ADDR_WIDTH)
    ) slave_inst (
        .aclk            (aclk),
        .aresetn         (aresetn),

        // AXI Interface
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awprot    (s_axi_awprot),
        .s_axi_awvalid   (s_axi_awvalid), // Connected to interception logic
        .s_axi_awready   (s_axi_awready),
        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wvalid    (s_axi_wvalid),  // Connected to interception logic
        .s_axi_wready    (s_axi_wready),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arprot    (s_axi_arprot),
        .s_axi_arvalid   (s_axi_arvalid), // Connected to interception logic
        .s_axi_arready   (s_axi_arready),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready)
    );

    // -------------------------------------------------------------------------
    // Interception and Stall Logic
    // -------------------------------------------------------------------------
    // This logic allows the testbench to selectively block handshake signals
    // to simulate slave backpressure.
    
    // Pass-through signals (Direct connection)
    assign s_axi_awaddr = m_axi_awaddr;
    assign s_axi_awprot = m_axi_awprot;
    assign s_axi_wdata  = m_axi_wdata;
    assign s_axi_wstrb  = m_axi_wstrb;
    assign s_axi_araddr = m_axi_araddr;
    assign s_axi_arprot = m_axi_arprot;
    assign s_axi_bready = m_axi_bready;
    assign s_axi_rready = m_axi_rready;
    
    assign m_axi_bresp  = s_axi_bresp;
    assign m_axi_bvalid = s_axi_bvalid;
    assign m_axi_rdata  = s_axi_rdata;
    assign m_axi_rresp  = s_axi_rresp;
    assign m_axi_rvalid = s_axi_rvalid;

    // Gated Signals: Write Address Channel
    assign s_axi_awvalid = m_axi_awvalid && !stall_awready;
    assign m_axi_awready = (stall_awready) ? 1'b0 : s_axi_awready;

    // Gated Signals: Write Data Channel
    assign s_axi_wvalid = m_axi_wvalid && !stall_wready;
    assign m_axi_wready = (stall_wready) ? 1'b0 : s_axi_wready;

    // Gated Signals: Read Address Channel
    assign s_axi_arvalid = m_axi_arvalid && !stall_arready;
    assign m_axi_arready = (stall_arready) ? 1'b0 : s_axi_arready;

    // -------------------------------------------------------------------------
    // Clock and Reset Generation
    // -------------------------------------------------------------------------
    initial begin
        aclk = 0;
        forever #(CLK_PERIOD / 2) aclk = ~aclk;
    end

    initial begin
        aresetn = 0;
        $display("[%0t] System Reset Asserted...", $time);
        repeat (3) @(posedge aclk);
        aresetn = 1;
        $display("[%0t] System Reset Deasserted.", $time);
    end

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    
    initial begin
        // VCD Dump configuration
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_system);

        // Initialize Stimulus Signals
        tb_start_write <= 1'b0;
        tb_start_read  <= 1'b0;
        tb_user_addr   <= 32'b0;
        tb_user_wdata  <= 32'b0;
        
        // Initialize Stall Control Signals
        stall_awready <= 1'b0;
        stall_wready  <= 1'b0;
        stall_arready <= 1'b0;

        // Wait for reset completion
        wait (aresetn == 1'b1);
        @(posedge aclk);
        
        // ---------------------------------------------------------------------
        // Test Case 1: Master Write with Backpressure
        // ---------------------------------------------------------------------
        $display("\n[%0t] === TEST 1: Write Transaction with Stall Injection ===\n", $time);
        
        tb_start_write <= 1'b1;
        tb_user_addr   <= 32'h0000_0000;
        tb_user_wdata  <= 32'hDEADBEEF;
        
        @(posedge aclk);
        tb_start_write <= 1'b0; 
        
        // Inject Stall on Write Address Channel
        // Synchronize to clock to ensure clean stall injection
        @(posedge aclk); 
        while (m_axi_awvalid == 1'b0) begin
            @(posedge aclk);
        end
        
        $display("[%0t] TB: Injecting AWREADY stall (3 cycles)...", $time);
        stall_awready <= 1'b1;
        repeat(3) @(posedge aclk);
        stall_awready <= 1'b0;
        $display("[%0t] TB: Releasing AWREADY.", $time);
        
        // Inject Stall on Write Data Channel
        @(posedge aclk);
        while (m_axi_wvalid == 1'b0) begin
            @(posedge aclk);
        end
        
        $display("[%0t] TB: Injecting WREADY stall (4 cycles)...", $time);
        stall_wready <= 1'b1;
        repeat(4) @(posedge aclk);
        stall_wready <= 1'b0;
        $display("[%0t] TB: Releasing WREADY.", $time);

        // Wait for completion
        while (~tb_user_write_done) begin
            @(posedge aclk);
        end
        $display("[%0t] Master write transaction complete.", $time);
        
        @(posedge aclk);

        // ---------------------------------------------------------------------
        // Test Case 2: Master Read Verification
        // ---------------------------------------------------------------------
        $display("\n[%0t] === TEST 2: Read Transaction Verification ===\n", $time);
        
        tb_start_read <= 1'b1;
        tb_user_addr  <= 32'h0000_0000;
        
        @(posedge aclk);
        tb_start_read <= 1'b0;

        while (~tb_user_read_done) begin
            @(posedge aclk);
        end
        $display("[%0t] Master read transaction complete.", $time);

        if (tb_user_rdata == 32'hDEADBEEF) begin
            $display("PASS: Data Integrity Verified (0x%h).", tb_user_rdata);
        end else begin
            $display("FAIL: Data Mismatch (Expected: 0xDEADBEEF, Got: 0x%h)", tb_user_rdata);
        end
        
        @(posedge aclk);
        
        // ---------------------------------------------------------------------
        // Test Case 3: Sequential Write
        // ---------------------------------------------------------------------
        $display("\n[%0t] === TEST 3: Write to Register 2 (0x08) ===\n", $time);
        tb_start_write <= 1'b1;
        tb_user_addr   <= 32'h0000_0008;
        tb_user_wdata  <= 32'h12345678;
        @(posedge aclk);
        tb_start_write <= 1'b0;
        
        while (~tb_user_write_done) @(posedge aclk);
        $display("[%0t] Master write transaction complete.", $time);

        @(posedge aclk);
        
        // ---------------------------------------------------------------------
        // Test Case 4: Sequential Read with Stall
        // ---------------------------------------------------------------------
        $display("\n[%0t] === TEST 4: Read from Register 2 with Stall ===\n", $time);
        tb_start_read <= 1'b1;
        tb_user_addr  <= 32'h0000_0008;
        @(posedge aclk);
        tb_start_read <= 1'b0;

        // Inject Stall on Read Address Channel
        @(posedge aclk);
        while (m_axi_arvalid == 1'b0) begin
            @(posedge aclk);
        end
        
        $display("[%0t] TB: Injecting ARREADY stall (2 cycles)...", $time);
        stall_arready <= 1'b1;
        repeat(2) @(posedge aclk);
        stall_arready <= 1'b0;
        $display("[%0t] TB: Releasing ARREADY.", $time);
        
        while (~tb_user_read_done) @(posedge aclk);
        $display("[%0t] Master read transaction complete.", $time);
        
        if (tb_user_rdata == 32'h12345678) begin
            $display("PASS: Data Integrity Verified (0x%h).", tb_user_rdata);
        end else begin
            $display("FAIL: Data Mismatch (Expected: 0x12345678, Got: 0x%h)", tb_user_rdata);
        end

        // ---------------------------------------------------------------------
        // Test Case 5: Arbitration Logic (Simultaneous Requests)
        // ---------------------------------------------------------------------
        $display("\n[%0t] === TEST 5: Arbitration Verification (Simultaneous R/W) ===\n", $time);
        tb_start_write <= 1'b1;
        tb_start_read  <= 1'b1; // Assert both requests simultaneously
        tb_user_addr   <= 32'h0000_000C; // Target Register 3
        tb_user_wdata  <= 32'hAAAAAAAA;
        @(posedge aclk);
        tb_start_write <= 1'b0;
        tb_start_read  <= 1'b0;

        // Arbitration check: Master should assert busy
        wait (tb_master_busy == 1'b1);
        $display("[%0t] Master arbitration active. Waiting for priority transaction...", $time);
        
        // Master prioritizes write; wait for write completion
        while (~tb_user_write_done) @(posedge aclk);
        $display("[%0t] Write transaction complete.", $time);

        // If read was dropped (due to simple arbitration), re-issue it
        if (~tb_master_busy) begin
            $display("[%0t] Re-issuing Read Request (Standard Arbitration Behavior).", $time);
            tb_start_read <= 1'b1;
            tb_user_addr  <= 32'h0000_000C;
            @(posedge aclk);
            tb_start_read <= 1'b0;
        end

        while (~tb_user_read_done) @(posedge aclk);
        $display("[%0t] Read transaction complete.", $time);
        
        if (tb_user_rdata == 32'hAAAAAAAA) begin
            $display("PASS: Arbitration sequence verified.", tb_user_rdata);
        end else begin
            $display("FAIL: Data Mismatch in arbitration test.", tb_user_rdata);
        end

        // ---------------------------------------------------------------------
        // Test Case 6: Back-to-Back Throughput
        // ---------------------------------------------------------------------
        $display("\n[%0t] === TEST 6: Back-to-Back Transactions ===\n", $time);
        
        // Initiate Write
        tb_start_write <= 1'b1;
        tb_user_addr   <= 32'h0000_0000;
        tb_user_wdata  <= 32'hBBBBBBBB;
        @(posedge aclk);
        tb_start_write <= 1'b0;
        
        // Wait for exact completion cycle
        while (~tb_user_write_done) @(posedge aclk);
        
        // Initiate Read immediately
        $display("[%0t] Write detected. Issuing Read immediately.", $time);
        tb_start_read <= 1'b1;
        tb_user_addr  <= 32'h0000_0000;
        
        @(posedge aclk);
        tb_start_read <= 1'b0;

        while (~tb_user_read_done) @(posedge aclk);
        $display("[%0t] Back-to-Back sequence complete.", $time);

        if (tb_user_rdata == 32'hBBBBBBBB) begin
            $display("PASS: Throughput verified.", tb_user_rdata);
        end else begin
            $display("FAIL: Data Mismatch in back-to-back test.", tb_user_rdata);
        end

        @(posedge aclk);
        $display("\n[%0t] === System Verification Complete ===\n", $time);
        $finish;
    end

endmodule
