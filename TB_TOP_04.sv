`timescale 1ns/1ps
`include "BOS_HEADER.svh"

module TB_TOP_04;

  // ---------------------------------------------------------
  // Parameters & Signals
  // ---------------------------------------------------------
  parameter ADDR_W = `BOS_DEF_ADDR_WIDTH;
  parameter DATA_W = `BOS_DEF_DATA_WIDTH;
  parameter ID_W   = `BOS_DEF_ADDR_ID_WIDTH;
  
  // Define Valid Address Range for the simulated Slave
  parameter logic [ADDR_W-1:0] ADDR_MIN = 16'h1000;
  parameter logic [ADDR_W-1:0] ADDR_MAX = 16'h1FFF;

  logic clk_axi, rst_n_axi;
  logic clk_apb, rst_n_apb;
  
  // AXI Signals
  logic [ADDR_W-1:0] aw_addr, ar_addr;
  logic [ID_W-1:0]   aw_id, ar_id;
  logic [DATA_W-1:0] w_data, r_data;
  logic              aw_valid, aw_ready, w_valid, w_ready, w_last;
  logic              ar_valid, ar_ready, b_valid, b_ready, r_valid, r_ready;
  logic [1:0]        b_resp, r_resp;

  // APB Interface (Connected to DUT)
  logic [ADDR_W-1:0] p_addr;
  logic [DATA_W-1:0] p_wdata, p_rdata;
  logic              p_sel, p_enable, p_write, p_ready, p_slverr;

  // ---------------------------------------------------------
  // FSDB Waveform Dump
  // ---------------------------------------------------------
  initial begin
    $fsdbDumpfile("waveform_tb_top_04.fsdb");
    $fsdbDumpvars(0, TB_TOP_04, "+all");
  end

  // ---------------------------------------------------------
  // DUT Instantiation
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
  // Simulated APB Slave with Address Decoding Logic
  // ---------------------------------------------------------
  always @(posedge clk_apb) begin
    if (!rst_n_apb) begin
      p_ready  <= 1'b0;
    end else begin
      // Simple 1-cycle response for PREADY
      if (p_sel && p_enable && !p_ready) begin
        p_ready <= 1'b1;
      end else begin
        p_ready <= 1'b0;
      end
    end
  end

  // Assert PSLVERR if the address accessed is out of the valid range 
  assign p_slverr = (p_sel && (p_addr < ADDR_MIN || p_addr > ADDR_MAX)) ? 1'b1 : 1'b0;
  // Return dummy data only if address is valid 
  assign p_rdata  = (p_sel && !p_write && !p_slverr) ? 32'h5555_AAAA : 32'h0;

  // ---------------------------------------------------------
  // AXI Master Tasks
  // ---------------------------------------------------------
  task axi_push_write(input [ADDR_W-1:0] addr, input [DATA_W-1:0] data);
    begin
      @(posedge clk_axi);
      aw_valid = 1; aw_addr = addr; aw_id = 2'b01;
      w_valid  = 1; w_data = data; w_last = 1;
      @(posedge clk_axi);
      aw_valid = 0; w_valid = 0; w_last = 0;
    end
  endtask

  task axi_push_read(input [ADDR_W-1:0] addr);
    begin
      @(posedge clk_axi);
      ar_valid = 1; ar_addr = addr; ar_id = 2'b10;
      @(posedge clk_axi);
      ar_valid = 0;
    end
  endtask

  // ---------------------------------------------------------
  // Test Scenario: Valid vs Invalid Addresses
  // ---------------------------------------------------------
  initial begin
    rst_n_axi = 0; rst_n_apb = 0;
    aw_valid = 0; w_valid = 0; ar_valid = 0; b_ready = 1; r_ready = 1; w_last = 0;
    #100 rst_n_axi = 1; rst_n_apb = 1;
    #50;

    $display("--- TB_TOP_04: ADDRESS VALIDATION (Valid Range: %h - %h) ---", ADDR_MIN, ADDR_MAX);

    // CASE 1: Valid Write Address
    $display("[TB] Sending Write to VALID address 16'h1500...");
    axi_push_write(16'h1500, 32'h1111_2222);
    wait(b_valid);
    if (b_resp == 2'b00) $display("[SUCCESS] Received OKAY for valid address.");
    else $display("[ERROR] Received error for valid address!");

    #100;

    // CASE 2: Invalid Write Address (Out of Range)
    $display("[TB] Sending Write to INVALID address 16'h5000...");
    axi_push_write(16'h5000, 32'hDEAD_BEEF);
    wait(b_valid);
    // Bridge controller maps PSLVERR to AXI BRESP[1] (SLVERR) [cite: 63, 66, 80, 109]
    if (b_resp == 2'b10) $display("[SUCCESS] Received SLVERR for invalid write address.");
    else $display("[ERROR] BRESP mismatch! Got: %b, Expected: 10", b_resp);

    #100;

    // CASE 3: Invalid Read Address
    $display("[TB] Sending Read to INVALID address 16'h0010...");
    axi_push_read(16'h0010);
    wait(r_valid);
    // Bridge controller maps PSLVERR to AXI RRESP[1] (SLVERR) [cite: 81, 109]
    if (r_resp == 2'b10) $display("[SUCCESS] Received SLVERR for invalid read address.");
    else $display("[ERROR] RRESP mismatch! Got: %b, Expected: 10", r_resp);

    #200;
    $finish;
  end

endmodule : TB_TOP_04