`timescale 1ns/1ps
`include "BOS_HEADER.svh"

module TB_TOP_01;

  // ---------------------------------------------------------
  // Parameters & Signals (Derived from BOS_HEADER.svh [cite: 113])
  // ---------------------------------------------------------
  parameter ADDR_W = `BOS_DEF_ADDR_WIDTH;      // 16 bits [cite: 113]
  parameter DATA_W = `BOS_DEF_DATA_WIDTH;      // 32 bits [cite: 113]
  parameter ID_W   = `BOS_DEF_ADDR_ID_WIDTH;   // 2 bits [cite: 113]
  parameter STRB_W = `BOS_DEF_STRB_WIDTH;      // 4 bits [cite: 113]

  // Clock & Reset
  logic clk_axi, rst_n_axi;
  logic clk_apb, rst_n_apb;
  
  // AXI Write Channels
  logic              aw_valid, aw_ready;
  logic [ADDR_W-1:0] aw_addr;
  logic [ID_W-1:0]   aw_id;
  logic              w_valid, w_ready, w_last;
  logic [DATA_W-1:0] w_data;
  logic [STRB_W-1:0] w_strb;
  logic              b_valid, b_ready;
  logic [ID_W-1:0]   b_id;
  logic [1:0]        b_resp;

  // AXI Read Channels
  logic              ar_valid, ar_ready;
  logic [ADDR_W-1:0] ar_addr;
  logic [ID_W-1:0]   ar_id;
  logic              r_valid, r_ready, r_last_out;
  logic [DATA_W-1:0] r_data;
  logic [ID_W-1:0]   r_id;
  logic [1:0]        r_resp;

  // APB Interface
  logic [ADDR_W-1:0] p_addr;
  logic [DATA_W-1:0] p_wdata;
  logic [STRB_W-1:0] p_strb;
  logic              p_sel, p_enable, p_write, p_ready, p_slverr;
  logic [DATA_W-1:0] p_rdata;

  // ---------------------------------------------------------
  // FSDB Waveform Dump (Verdi/VCS specific)
  // ---------------------------------------------------------
  initial begin
    $fsdbDumpfile("waveform_tb_top_01.fsdb");
    $fsdbDumpvars(0, TB_TOP_01, "+all"); // Dump all signals including memories/structs
  end

  // ---------------------------------------------------------
  // Simple Slave Memory Model (Associative Array)
  // ---------------------------------------------------------
  logic [DATA_W-1:0] slave_mem [logic [ADDR_W-1:0]]; 

  // ---------------------------------------------------------
  // DUT Instantiation [cite: 83]
  // ---------------------------------------------------------
  AXI_TO_APB_BRIDGE dut (
    .I_A_CLK(clk_axi),
    .I_P_CLK(clk_apb),
    .I_A_RESET_N(rst_n_axi),
    .I_P_RESET_N(rst_n_apb),
    // AXI Write Channels [cite: 85, 87, 88]
    .I_AW_VALID(aw_valid), .I_AW_ADDR(aw_addr), .I_AW_ID(aw_id), .O_AW_READY(aw_ready),
    .I_W_VALID(w_valid), .I_W_DATA(w_data), .I_W_STRB(w_strb), .O_W_READY(w_ready),
    .I_B_READY(b_ready), .O_B_RESP(b_resp), .O_B_ID(b_id), .O_B_VALID(b_valid),
    // AXI Read Channels [cite: 89, 91]
    .I_AR_VALID(ar_valid), .I_AR_ADDR(ar_addr), .I_AR_ID(ar_id), .O_AR_READY(ar_ready),
    .I_R_READY(r_ready), .O_R_VALID(r_valid), .O_R_DATA(r_data), .O_R_ID(r_id), .O_R_RESP(r_resp), .O_R_LAST(r_last_out),
    // APB Interface [cite: 92, 94]
    .O_P_ADDR(p_addr), .O_P_WDATA(p_wdata), .O_P_STRB(p_strb), .O_P_SEL(p_sel),
    .O_P_ENABLE(p_enable), .O_P_WRITE(p_write), .I_P_READY(p_ready), .I_P_SLVERR(p_slverr), .I_P_RDATA(p_rdata)
  );

  // ---------------------------------------------------------
  // Clock & Reset Generation
  // ---------------------------------------------------------
  initial begin
    clk_axi = 0;
    forever #5 clk_axi = ~clk_axi; // 100MHz AXI Clock
  end

  initial begin
    clk_apb = 0;
    #2; 
    forever #12 clk_apb = ~clk_apb; // ~41.6MHz APB Clock
  end

  // ---------------------------------------------------------
  // APB Slave behavior
  // ---------------------------------------------------------
  always @(posedge clk_apb) begin
    if (!rst_n_apb) begin
      p_ready <= 1'b0;
    end else begin
      if (p_sel && p_enable && !p_ready) begin
        p_ready <= 1'b1;
        if (p_write) slave_mem[p_addr] = p_wdata; // Store on APB Write
      end else begin
        p_ready <= 1'b0;
      end
    end
  end
  // Data out on APB Read
  assign p_rdata = (p_sel && !p_write) ? (slave_mem.exists(p_addr) ? slave_mem[p_addr] : 32'hDEADBEEF) : 32'h0;
  assign p_slverr = 1'b0;

  // ---------------------------------------------------------
  // AXI Master Tasks
  // ---------------------------------------------------------
  task axi_push_aw(input [ADDR_W-1:0] addr, input [ID_W-1:0] id);
    begin
      @(posedge clk_axi);
      while (!aw_ready) @(posedge clk_axi);
      aw_valid = 1'b1; aw_addr = addr; aw_id = id;
      @(posedge clk_axi);
      aw_valid = 1'b0;
    end
  endtask

  task axi_push_w(input [DATA_W-1:0] data, input [STRB_W-1:0] strb);
    begin
      @(posedge clk_axi);
      while (!w_ready) @(posedge clk_axi);
      w_valid = 1'b1; w_data = data; w_strb = strb; w_last = 1'b1;
      @(posedge clk_axi);
      w_valid = 1'b0; w_last = 1'b0;
    end
  endtask

  task axi_push_ar(input [ADDR_W-1:0] addr, input [ID_W-1:0] id);
    begin
      @(posedge clk_axi);
      while (!ar_ready) @(posedge clk_axi);
      ar_valid = 1'b1; ar_addr = addr; ar_id = id;
      @(posedge clk_axi);
      ar_valid = 1'b0;
    end
  endtask

  // ---------------------------------------------------------
  // Test Scenario: Single Write then Read back
  // ---------------------------------------------------------
  initial begin
    // Initial State
    rst_n_axi = 0; rst_n_apb = 0;
    aw_valid = 0; w_valid = 0; ar_valid = 0;
    b_ready = 1; r_ready = 1; w_last = 0;
    
    #100;
    rst_n_axi = 1; rst_n_apb = 1;
    #50;

    $display("--- TB_TOP_01: STARTING SINGLE WRITE/READ TEST ---");

    // 1. Write Transaction to Address 0x8800
    axi_push_aw(16'h8800, 2'b01);
    axi_push_w(32'hA5A5_B6B6, 4'hF);
    
    wait(b_valid); // Wait for AXI Write Response [cite: 89]
    $display("[TB_TOP_01] Write Transaction Finished. B_ID: %h", b_id);

    #100;

    // 2. Read Transaction from Address 0x8800
    axi_push_ar(16'h8800, 2'b01);
    
    wait(r_valid); // Wait for AXI Read Valid [cite: 91]
    if (r_data == 32'hA5A5_B6B6)
      $display("[TB_TOP_01 SUCCESS] Read matching data: %h from 0x8800", r_data);
    else
      $display("[TB_TOP_01 ERROR] Data mismatch! Read: %h, Expected: A5A5B6B6", r_data);

    #200;
    $display("--- TB_TOP_01: FINISHED ---");
    $finish;
  end

endmodule : TB_TOP_01