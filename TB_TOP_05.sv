`timescale 1ns/1ps
`include "BOS_HEADER.svh"

module TB_TOP_05;

  // ---------------------------------------------------------
  // Parameters & Signals
  // ---------------------------------------------------------
  parameter ADDR_W = `BOS_DEF_ADDR_WIDTH;
  parameter DATA_W = `BOS_DEF_DATA_WIDTH;
  parameter ID_W   = `BOS_DEF_ADDR_ID_WIDTH;

  logic clk_axi, rst_n_axi;
  logic clk_apb, rst_n_apb;
  
  // AXI Signals
  logic [ADDR_W-1:0] aw_addr, ar_addr;
  logic [ID_W-1:0]   aw_id, ar_id;
  logic [DATA_W-1:0] w_data, r_data;
  logic              aw_valid, aw_ready, w_valid, w_ready, w_last;
  logic              ar_valid, ar_ready, b_valid, b_ready, r_valid, r_ready;
  logic [1:0]        b_resp, r_resp;

  // APB Interface
  logic [ADDR_W-1:0] p_addr;
  logic [DATA_W-1:0] p_wdata, p_rdata;
  logic              p_sel, p_enable, p_write, p_ready, p_slverr;

  // ---------------------------------------------------------
  // FSDB Waveform Dump
  // ---------------------------------------------------------
  initial begin
    $fsdbDumpfile("waveform_tb_top_05.fsdb");
    $fsdbDumpvars(0, TB_TOP_05, "+all");
  end

  // ---------------------------------------------------------
  // REAL DATA STORAGE: Associative Array
  // ---------------------------------------------------------
  // This array acts as the real memory of your simulated peripheral.
  logic [DATA_W-1:0] slave_mem [logic [ADDR_W-1:0]]; 

  // ---------------------------------------------------------
  // DUT Instantiation [cite: 107]
  // ---------------------------------------------------------
  AXI_TO_APB_BRIDGE dut (
    .I_A_CLK(clk_axi), .I_P_CLK(clk_apb),
    .I_A_RESET_N(rst_n_axi), .I_P_RESET_N(rst_n_apb),
    .I_AW_VALID(aw_valid), .I_AW_ADDR(aw_addr), .I_AW_ID(aw_id), .O_AW_READY(aw_ready),
    .I_W_VALID(w_valid), .I_W_DATA(w_data), .I_W_STRB(4'hF), .O_W_READY(w_ready),
    .I_B_READY(b_ready), .O_B_VALID(b_valid), .O_B_RESP(b_resp),
    .I_AR_VALID(ar_valid), .I_AR_ADDR(ar_addr), .I_AR_ID(ar_id), .O_AR_READY(ar_ready),
    .I_R_READY(r_ready), .O_R_VALID(r_valid), .O_R_DATA(r_data), .O_R_RESP(r_resp),
    .O_P_ADDR(p_addr), .O_P_WDATA(p_wdata), .O_P_SEL(p_sel), .O_P_ENABLE(p_enable), 
    .O_P_WRITE(p_write), .I_P_READY(p_ready), .I_P_RDATA(p_rdata), .I_P_SLVERR(p_slverr)
  );

  // Clock Generation
  initial begin clk_axi = 0; forever #5 clk_axi = ~clk_axi; end
  initial begin clk_apb = 0; #2; forever #12 clk_apb = ~clk_apb; end

  // ---------------------------------------------------------
  // Simulated APB Slave with Real Data Write/Read
  // ---------------------------------------------------------
  int wait_cycles = 0;

  always @(posedge clk_apb) begin
    if (!rst_n_apb) begin
      p_ready <= 1'b0;
      wait_cycles <= 0;
    end else begin
      // Access Phase detection [cite: 53, 56]
      if (p_sel && p_enable && !p_ready) begin
        if (wait_cycles == 0) begin
          wait_cycles <= $urandom_range(3, 8); // Random latency
          p_ready <= 1'b0;
        end else if (wait_cycles == 1) begin
          p_ready <= 1'b1; // Trigger PREADY [cite: 36]
          wait_cycles <= 0;
          
          // REAL DATA WRITE LOGIC
          if (p_write) begin
            slave_mem[p_addr] = p_wdata;
            $display("[Slave] REAL WRITE: Addr=%h, Data=%h at %0t", p_addr, p_wdata, $time);
          end
        end else begin
          wait_cycles <= wait_cycles - 1;
          p_ready <= 1'b0;
        end
      end else begin
        p_ready <= 1'b0;
      end
    end
  end

  // REAL DATA READ LOGIC
  assign p_rdata = (p_sel && !p_write && p_ready) ? 
                   (slave_mem.exists(p_addr) ? slave_mem[p_addr] : 32'hDEADBEEF) : 32'h0;
  assign p_slverr = 1'b0;

  // ---------------------------------------------------------
  // AXI Master Tasks
  // ---------------------------------------------------------
  task axi_push_write(input [ADDR_W-1:0] addr, input [DATA_W-1:0] data);
    begin
      @(posedge clk_axi);
      while (!aw_ready || !w_ready) @(posedge clk_axi);
      aw_valid = 1; aw_addr = addr; aw_id = $urandom;
      w_valid  = 1; w_data = data; w_last = 1;
      @(posedge clk_axi);
      aw_valid = 0; w_valid = 0; w_last = 0;
    end
  endtask

  task axi_push_read(input [ADDR_W-1:0] addr);
    begin
      @(posedge clk_axi);
      while (!ar_ready) @(posedge clk_axi);
      ar_valid = 1; ar_addr = addr; ar_id = $urandom;
      @(posedge clk_axi);
      ar_valid = 0;
    end
  endtask

  // ---------------------------------------------------------
  // Test Scenario: Mixed Real Data Traffic
  // ---------------------------------------------------------
  initial begin
    int i;
    logic [DATA_W-1:0] test_val;
    
    rst_n_axi = 0; rst_n_apb = 0;
    aw_valid = 0; w_valid = 0; ar_valid = 0; b_ready = 1; r_ready = 1; w_last = 0;
    #100 rst_n_axi = 1; rst_n_apb = 1;
    #50;

    $display("--- TB_TOP_05: REAL DATA MIXED TRAFFIC ---");

    for (i = 0; i < 8; i++) begin
      test_val = $urandom;
      // Write real data
      axi_push_write(i*4, test_val);
      
      // Read it back immediately (will be queued in FIFOs)
      axi_push_read(i*4);
      
      repeat($urandom_range(2, 4)) @(posedge clk_axi);
    end

    // Monitor results
    #2000; 
    $display("--- TB_TOP_05: FINISHED ---");
    $finish;
  end

endmodule : TB_TOP_05