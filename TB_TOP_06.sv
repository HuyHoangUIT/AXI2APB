`timescale 1ns/1ps
`include "BOS_HEADER.svh"

module TB_TOP_06;

  // ---------------------------------------------------------
  // Parameters & Signals
  // ---------------------------------------------------------
  parameter ADDR_W = `BOS_DEF_ADDR_WIDTH;      // [cite: 113]
  parameter DATA_W = `BOS_DEF_DATA_WIDTH;      // [cite: 113]
  parameter ID_W   = `BOS_DEF_ADDR_ID_WIDTH;   // [cite: 113]
  parameter DEPTH  = (1 << `BOS_DEF_FIFO_DEPTH); // Depth = 16 [cite: 113]

  logic clk_axi, rst_n_axi;
  logic clk_apb, rst_n_apb;
  
  // AXI Signals
  logic [ADDR_W-1:0] aw_addr, ar_addr;
  logic [ID_W-1:0]   aw_id, ar_id;
  logic [DATA_W-1:0] w_data, r_data;
  logic              aw_valid, aw_ready, w_valid, w_ready, w_last;
  logic              ar_valid, ar_ready, b_valid, b_ready, r_valid, r_ready;

  // APB Interface
  logic [ADDR_W-1:0] p_addr;
  logic [DATA_W-1:0] p_wdata, p_rdata;
  logic              p_sel, p_enable, p_write, p_ready;

  // ---------------------------------------------------------
  // FSDB Waveform Dump
  // ---------------------------------------------------------
  initial begin
    $fsdbDumpfile("waveform_tb_top_06.fsdb");
    $fsdbDumpvars(0, TB_TOP_06, "+all");
  end

  // Slave Memory Model
  logic [DATA_W-1:0] slave_mem [logic [ADDR_W-1:0]]; 

  // ---------------------------------------------------------
  // DUT Instantiation
  // ---------------------------------------------------------
  AXI_TO_APB_BRIDGE dut (
    .I_A_CLK(clk_axi), .I_P_CLK(clk_apb),
    .I_A_RESET_N(rst_n_axi), .I_P_RESET_N(rst_n_apb),
    .I_AW_VALID(aw_valid), .I_AW_ADDR(aw_addr), .I_AW_ID(aw_id), .O_AW_READY(aw_ready),
    .I_W_VALID(w_valid), .I_W_DATA(w_data), .I_W_STRB(4'hF), .O_W_READY(w_ready),
    .I_B_READY(b_ready), .O_B_VALID(b_valid),
    .I_AR_VALID(ar_valid), .I_AR_ADDR(ar_addr), .I_AR_ID(ar_id), .O_AR_READY(ar_ready),
    .I_R_READY(r_ready), .O_R_VALID(r_valid), .O_R_DATA(r_data),
    .O_P_ADDR(p_addr), .O_P_WDATA(p_wdata), .O_P_SEL(p_sel), .O_P_ENABLE(p_enable), 
    .O_P_WRITE(p_write), .I_P_READY(p_ready), .I_P_RDATA(p_rdata), .I_P_SLVERR(1'b0)
  );

  // Clock Generation
  initial begin clk_axi = 0; forever #5 clk_axi = ~clk_axi; end
  initial begin clk_apb = 0; #2; forever #12 clk_apb = ~clk_apb; end

  // Simple APB Slave (Fast response)
  always @(posedge clk_apb) begin
    p_ready <= (p_sel && p_enable && !p_ready);
    if (p_sel && p_enable && p_write) slave_mem[p_addr] = p_wdata;
  end
  assign p_rdata = 32'hBEEF_CAFE;

  // ---------------------------------------------------------
  // Test Scenario: Backpressure Stress Test (FIFOs Full)
  // ---------------------------------------------------------
  initial begin
    int i;
    // Initial State: MASTER IS NOT READY TO RECEIVE RESPONSES
    rst_n_axi = 0; rst_n_apb = 0;
    aw_valid = 0; w_valid = 0; ar_valid = 0; 
    b_ready = 0; // [cite: 88] Disable Write Response readiness
    r_ready = 0; // [cite: 90] Disable Read Data readiness
    w_last = 0;
    
    #100 rst_n_axi = 1; rst_n_apb = 1;
    #50;

    $display("--- TB_TOP_06: STALLING B/R CHANNELS TO FILL ALL FIFOS ---");

    // Step 1: Push Write/Read requests until AW/W/AR FIFOs are Full
    // Since B/R FIFOs are not being cleared, they will fill up first.
    // Once B/R FIFOs are full, the Bridge Controller will stall, 
    // causing AW/W/AR FIFOs to eventually fill up too.
    for (i = 0; i < DEPTH + 5; i++) begin
      fork
        // Push Write
        begin
          if (aw_ready && w_ready) begin
            aw_valid = 1; aw_addr = i*4; aw_id = 2'b01;
            w_valid  = 1; w_data = i; w_last = 1;
            @(posedge clk_axi);
            aw_valid = 0; w_valid = 0; w_last = 0;
          end
        end
        // Push Read
        begin
          if (ar_ready) begin
            ar_valid = 1; ar_addr = i*4; ar_id = 2'b10;
            @(posedge clk_axi);
            ar_valid = 0;
          end
        end
      join
      
      $display("[TB] Cycle %0d: AW_Ready=%b, W_Ready=%b, AR_Ready=%b", i, aw_ready, w_ready, ar_ready);
      #10;
    end

    // Step 2: Check if system is stalled
    #200;
    if (!aw_ready && !w_ready && !ar_ready)
      $display("[SUCCESS] All Input FIFOs are FULL and system is stalled.");

    // Step 3: Now Master becomes READY - System should start moving again
    $display("[TB] Master is now READY. Clearing B and R FIFOs...");
    b_ready = 1; // [cite: 88]
    r_ready = 1; // [cite: 90]

    // Step 4: Verify that data starts flowing
    wait(r_valid || b_valid);
    $display("[SUCCESS] Data flow resumed after Master became Ready.");

    #500;
    $finish;
  end

endmodule : TB_TOP_06