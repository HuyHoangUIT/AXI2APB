`timescale 1ns/1ps
`include "BOS_HEADER.svh"

module TB_TOP_03;

  // ---------------------------------------------------------
  // Parameters & Signals
  // ---------------------------------------------------------
  parameter ADDR_W = `BOS_DEF_ADDR_WIDTH;
  parameter DATA_W = `BOS_DEF_DATA_WIDTH;
  parameter ID_W   = `BOS_DEF_ADDR_ID_WIDTH;
  parameter STRB_W = `BOS_DEF_STRB_WIDTH;
  parameter DEPTH  = (1 << `BOS_DEF_FIFO_DEPTH); // Depth = 16 [cite: 113]

  logic clk_axi, rst_n_axi;
  logic clk_apb, rst_n_apb;
  
  // AXI Channels
  logic [ADDR_W-1:0] aw_addr, ar_addr;
  logic [ID_W-1:0]   aw_id, ar_id;
  logic [DATA_W-1:0] w_data;
  logic              aw_valid, aw_ready, w_valid, w_ready, w_last;
  logic              ar_valid, ar_ready, b_valid, b_ready, r_valid, r_ready;
  logic [DATA_W-1:0] r_data;

  // APB Interface
  logic [ADDR_W-1:0] p_addr;
  logic [DATA_W-1:0] p_wdata, p_rdata;
  logic              p_sel, p_enable, p_write, p_ready;

  // FSDB Dump
  initial begin
    $fsdbDumpfile("waveform_tb_top_03.fsdb");
    $fsdbDumpvars(0, TB_TOP_03, "+all");
  end

  // Slave Memory Model
  logic [DATA_W-1:0] slave_mem [logic [ADDR_W-1:0]]; 

  // DUT Instantiation [cite: 83]
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

  // Simple APB Slave
  always @(posedge clk_apb) begin
    p_ready <= (p_sel && p_enable && !p_ready);
    if (p_sel && p_enable && p_write) slave_mem[p_addr] <= p_wdata;
  end
  assign p_rdata = (p_sel && !p_write) ? (slave_mem.exists(p_addr) ? slave_mem[p_addr] : 32'h0) : 32'h0;

  // ---------------------------------------------------------
  // Test Scenario: Simultaneous AW and AR
  // ---------------------------------------------------------
  initial begin
    int i;
    rst_n_axi = 0; rst_n_apb = 0;
    aw_valid = 0; w_valid = 0; ar_valid = 0; b_ready = 1; r_ready = 1; w_last = 0;
    #100 rst_n_axi = 1; rst_n_apb = 1;
    #50;

    $display("--- TB_TOP_03: SIMULTANEOUS AW & AR REQUESTS ---");

    for (i = 0; i < DEPTH; i++) begin
      @(posedge clk_axi);
      // Set AW, W, and AR VALID in the EXACT SAME cycle
      aw_valid = 1; aw_addr = i*4; aw_id = 2'b01;
      w_valid  = 1; w_data  = 32'hCAFE_0000 + i; w_last = 1;
      ar_valid = 1; ar_addr = i*4; ar_id = 2'b10;

      @(posedge clk_axi);
      aw_valid = 0; w_valid = 0; ar_valid = 0; w_last = 0;
      
      // Small delay to let APB finish or next burst
      #20; 
    end

    // Wait for all responses
    repeat(DEPTH * 2) begin
      @(posedge clk_axi);
      if (r_valid) $display("[TB] Read Data: %h", r_data);
      if (b_valid) $display("[TB] Write Resp Received");
    end

    #200;
    $display("--- TB_TOP_03: FINISHED ---");
    $finish;
  end

endmodule : TB_TOP_03