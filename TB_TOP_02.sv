`timescale 1ns/1ps
`include "BOS_HEADER.svh"

module TB_TOP_02;

  // ---------------------------------------------------------
  // Parameters & Signals
  // ---------------------------------------------------------
  parameter ADDR_W = `BOS_DEF_ADDR_WIDTH;
  parameter DATA_W = `BOS_DEF_DATA_WIDTH;
  parameter ID_W   = `BOS_DEF_ADDR_ID_WIDTH;
  parameter STRB_W = `BOS_DEF_STRB_WIDTH;
  parameter DEPTH  = (1 << `BOS_DEF_FIFO_DEPTH); // FIFO Depth = 16 

  // Clock & Reset
  logic clk_axi, rst_n_axi;
  logic clk_apb, rst_n_apb;
  
  // AXI Channels
  logic              aw_valid, aw_ready;
  logic [ADDR_W-1:0] aw_addr;
  logic [ID_W-1:0]   aw_id;
  logic              w_valid, w_ready, w_last;
  logic [DATA_W-1:0] w_data;
  logic [STRB_W-1:0] w_strb;
  logic              b_valid, b_ready;
  logic [ID_W-1:0]   b_id;
  logic [1:0]        b_resp;
  logic              ar_valid, ar_ready;
  logic [ADDR_W-1:0] ar_addr;
  logic [ID_W-1:0]   ar_id;
  logic              r_valid, r_ready, r_last_out;
  logic [DATA_W-1:0] r_data;
  logic [ID_W-1:0]   r_id;

  // APB Interface
  logic [ADDR_W-1:0] p_addr;
  logic [DATA_W-1:0] p_wdata;
  logic [STRB_W-1:0] p_strb;
  logic              p_sel, p_enable, p_write, p_ready, p_slverr;
  logic [DATA_W-1:0] p_rdata;

  // FSDB Dump
  initial begin
    $fsdbDumpfile("waveform_tb_top_02.fsdb");
    $fsdbDumpvars(0, TB_TOP_02, "+all");
  end

  // Slave Memory Model
  logic [DATA_W-1:0] slave_mem [logic [ADDR_W-1:0]]; 

  // DUT Instantiation
  AXI_TO_APB_BRIDGE dut (
    .I_A_CLK(clk_axi), .I_P_CLK(clk_apb),
    .I_A_RESET_N(rst_n_axi), .I_P_RESET_N(rst_n_apb),
    .I_AW_VALID(aw_valid), .I_AW_ADDR(aw_addr), .I_AW_ID(aw_id), .O_AW_READY(aw_ready),
    .I_W_VALID(w_valid), .I_W_DATA(w_data), .I_W_STRB(w_strb), .O_W_READY(w_ready),
    .I_B_READY(b_ready), .O_B_RESP(b_resp), .O_B_ID(b_id), .O_B_VALID(b_valid),
    .I_AR_VALID(ar_valid), .I_AR_ADDR(ar_addr), .I_AR_ID(ar_id), .O_AR_READY(ar_ready),
    .I_R_READY(r_ready), .O_R_VALID(r_valid), .O_R_DATA(r_data), .O_R_ID(r_id), .O_R_RESP(r_resp), .O_R_LAST(r_last_out),
    .O_P_ADDR(p_addr), .O_P_WDATA(p_wdata), .O_P_STRB(p_strb), .O_P_SEL(p_sel),
    .O_P_ENABLE(p_enable), .O_P_WRITE(p_write), .I_P_READY(p_ready), .I_P_SLVERR(p_slverr), .I_P_RDATA(p_rdata)
  );

  // Clock Generation
  initial begin clk_axi = 0; forever #5 clk_axi = ~clk_axi; end
  initial begin clk_apb = 0; #2; forever #12 clk_apb = ~clk_apb; end

  // Slow APB Slave (Adds 2 cycles delay per access to help fill FIFO)
  int delay_cnt = 0;
  always @(posedge clk_apb) begin
    if (!rst_n_apb) begin
      p_ready <= 0;
      delay_cnt <= 0;
    end else begin
      if (p_sel && p_enable && !p_ready) begin
        if (delay_cnt == 2) begin
          p_ready <= 1;
          delay_cnt <= 0;
          if (p_write) slave_mem[p_addr] = p_wdata;
        end else begin
          delay_cnt <= delay_cnt + 1;
        end
      end else begin
        p_ready <= 0;
      end
    end
  end
  assign p_rdata = (p_sel && !p_write && p_ready) ? (slave_mem.exists(p_addr) ? slave_mem[p_addr] : 32'h0) : 32'h0;

  // AXI Master Tasks
  task axi_push_aw(input [ADDR_W-1:0] addr, input [ID_W-1:0] id);
    begin
      @(posedge clk_axi);
      while (!aw_ready) @(posedge clk_axi);
      aw_valid = 1; aw_addr = addr; aw_id = id;
      @(posedge clk_axi);
      aw_valid = 0;
    end
  endtask

  task axi_push_w(input [DATA_W-1:0] data);
    begin
      @(posedge clk_axi);
      while (!w_ready) @(posedge clk_axi);
      w_valid = 1; w_data = data; w_strb = 4'hF; w_last = 1;
      @(posedge clk_axi);
      w_valid = 0; w_last = 0;
    end
  endtask

  task axi_push_ar(input [ADDR_W-1:0] addr, input [ID_W-1:0] id);
    begin
      @(posedge clk_axi);
      while (!ar_ready) @(posedge clk_axi);
      ar_valid = 1; ar_addr = addr; ar_id = id;
      @(posedge clk_axi);
      ar_valid = 0;
    end
  endtask

  // ---------------------------------------------------------
  // Test Scenario: Fill FIFO to Depth and Burst Read
  // ---------------------------------------------------------
  initial begin
    int i;
    rst_n_axi = 0; rst_n_apb = 0;
    aw_valid = 0; w_valid = 0; ar_valid = 0; b_ready = 1; r_ready = 1;
    #100 rst_n_axi = 1; rst_n_apb = 1;
    #50;

    $display("--- TB_TOP_02: FILLING FIFO TO DEPTH (%0d) ---", DEPTH);

    // Step 1: Push N write requests as fast as possible to fill FIFO
    for (i = 0; i < DEPTH; i++) begin
      fork
        axi_push_aw(i*4, 2'b01);
        axi_push_w(32'hAAAA_0000 + i);
      join
      $display("[TB] Pushed Write Request %0d", i);
    end

    // Wait for all Write Responses
    for (i = 0; i < DEPTH; i++) begin
      wait(b_valid);
      @(posedge clk_axi);
    end
    $display("[TB] All %0d Writes completed on APB.", DEPTH);

    #200;

    // Step 2: Push N read requests
    $display("--- TB_TOP_02: STARTING %0d READ REQUESTS ---", DEPTH);
    for (i = 0; i < DEPTH; i++) begin
      axi_push_ar(i*4, 2'b01);
    end

    // Step 3: Collect and verify Read Data
    for (i = 0; i < DEPTH; i++) begin
      wait(r_valid);
      if (r_data == (32'hAAAA_0000 + i))
        $display("[SUCCESS] Read %0d: Data %h matches.", i, r_data);
      else
        $display("[ERROR] Read %0d: Got %h, Expected %h", i, r_data, (32'hAAAA_0000 + i));
      @(posedge clk_axi);
    end

    #200;
    $display("--- TB_TOP_02: FINISHED ---");
    $finish;
  end

endmodule : TB_TOP_02