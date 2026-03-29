//---------------------------------------------------------------------- 
// Company: BOS Semiconductors
// Author: Le Phuong Khanh, Nguyen Ngoc Huy Hoang, Nguyen Hoan Khanh
// Description: This is a Bridge use for communication between AXI and APB (protocol converter).
//----------------------------------------------------------------------

`timescale 1ns/1ps
`include "BOS_HEADER.svh"

module AXI_TO_APB_BRIDGE
(
  // System signals
  input                                             I_A_CLK,
  input                                             I_P_CLK,
  input                                             I_A_RESET_N,
  input                                             I_P_RESET_N,

  // AXI Write Address Channel
  input                                             I_AW_VALID,
  input  [`BOS_DEF_ADDR_WIDTH - 1 : 0]              I_AW_ADDR,
  input  [`BOS_DEF_ADDR_ID_WIDTH - 1 : 0]           I_AW_ID,
  output logic                                      O_AW_READY,

  // AXI Write Data Channel
  input                                             I_W_VALID,
  input  [`BOS_DEF_DATA_WIDTH - 1 : 0]              I_W_DATA,
  input  [`BOS_DEF_DATA_WIDTH/8 - 1 : 0]            I_W_STRB,
  output logic                                      O_W_READY,

  // AXI Write Response Channel
  input                                             I_B_READY,
  output logic [1 : 0]                              O_B_RESP,
  output logic [`BOS_DEF_ADDR_ID_WIDTH - 1 : 0]     O_B_ID,
  output logic                                      O_B_VALID,

  // AXI Read Address Channel
  input                                             I_AR_VALID,
  input  [`BOS_DEF_ADDR_WIDTH - 1 : 0]              I_AR_ADDR,
  input  [`BOS_DEF_ADDR_ID_WIDTH - 1 : 0]           I_AR_ID,
  output logic                                      O_AR_READY,

  // AXI Read Data Channel
  input                                             I_R_READY,
  output logic                                      O_R_VALID,
  output logic [`BOS_DEF_DATA_WIDTH - 1 : 0]        O_R_DATA,
  output logic [`BOS_DEF_ADDR_ID_WIDTH - 1 : 0]     O_R_ID,
  output logic [1 : 0]                              O_R_RESP,
  output logic                                      O_R_LAST,

  // APB Interface
  output logic [`BOS_DEF_ADDR_WIDTH - 1 : 0]        O_P_ADDR,
  output logic [`BOS_DEF_DATA_WIDTH - 1 : 0]        O_P_WDATA,
  output logic [`BOS_DEF_STRB_WIDTH - 1 : 0]        O_P_STRB,
  output logic                                      O_P_SEL,
  output logic                                      O_P_ENABLE,
  output logic                                      O_P_WRITE,
  input                                             I_P_READY,
  input                                             I_P_SLVERR,
  input  [`BOS_DEF_DATA_WIDTH - 1 : 0]              I_P_RDATA
);

  localparam BOS_PARA_AW_AR_DATA_WIDTH  = `BOS_DEF_ADDR_WIDTH + `BOS_DEF_ADDR_ID_WIDTH;
  localparam BOS_PARA_W_DATA_WIDTH      = `BOS_DEF_DATA_WIDTH + `BOS_DEF_STRB_WIDTH;
  localparam BOS_PARA_B_DATA_WIDTH      = `BOS_DEF_WRITE_HANDLER_WIDTH;
  localparam BOS_PARA_R_DATA_WIDTH = `BOS_DEF_READ_HANDLER_WIDTH;

  state_t state;
  logic pop_write, pop_read;
  logic b_push, r_push;

  // FIFO Status signals
  logic aw_empty, w_empty, ar_empty;
  logic aw_almost_empty, w_almost_empty, ar_almost_empty;
  logic b_full, r_full;
  logic b_almost_full, r_almost_full;

  // Internal Data signals
  logic [BOS_PARA_AW_AR_DATA_WIDTH  - 1 : 0] aw_data, ar_data;
  logic [BOS_PARA_W_DATA_WIDTH - 1 : 0] w_data;
  logic [BOS_PARA_B_DATA_WIDTH - 1 : 0] b_data_in, b_data_out;
  logic [BOS_PARA_R_DATA_WIDTH - 1 : 0] r_data_in, r_data_out;

  logic aw_ready_n, w_ready_n, ar_ready_n, b_valid_n, r_valid_n;

  // --- FIFOs Instantiation ---
  // AW FIFO
  BOS_ASYNC_GRAY_FIFO #(
    .BOS_PARA_DATA_W(BOS_PARA_AW_AR_DATA_WIDTH),
    .BOS_PARA_ADDR_W(`BOS_DEF_FIFO_DEPTH)
  ) u_ASYNC_FF_AW (
    .I_WR_CLK(I_A_CLK), 
    .I_RD_CLK(I_P_CLK), 
    .I_WR_RESET_N(I_A_RESET_N), 
    .I_RD_RESET_N(I_P_RESET_N),
    .I_WR_EN(I_AW_VALID), 
    .I_RD_EN(pop_write), 
    .I_WR_DATA({I_AW_ID, I_AW_ADDR}), 
    .O_RD_DATA(aw_data),
    .O_FIFO_ALMOST_EMPTY(aw_almost_empty), 
    .O_FIFO_FULL(aw_ready_n), .O_FIFO_EMPTY(aw_empty)
  );

  // W FIFO
  BOS_ASYNC_GRAY_FIFO #(
    .BOS_PARA_DATA_W(BOS_PARA_W_DATA_WIDTH),
    .BOS_PARA_ADDR_W(`BOS_DEF_FIFO_DEPTH)
  ) u_ASYNC_FF_W (
    .I_WR_CLK(I_A_CLK), 
    .I_RD_CLK(I_P_CLK), 
    .I_WR_RESET_N(I_A_RESET_N), 
    .I_RD_RESET_N(I_P_RESET_N),
    .I_WR_EN(I_W_VALID), 
    .I_RD_EN(pop_write), 
    .I_WR_DATA({I_W_DATA, I_W_STRB}), 
    .O_RD_DATA(w_data),
    .O_FIFO_ALMOST_EMPTY(w_almost_empty), 
    .O_FIFO_FULL(w_ready_n), 
    .O_FIFO_EMPTY(w_empty)
  );

  // B FIFO
  BOS_ASYNC_GRAY_FIFO #(
    .BOS_PARA_DATA_W(BOS_PARA_B_DATA_WIDTH),
    .BOS_PARA_ADDR_W(`BOS_DEF_FIFO_DEPTH)
  ) u_ASYNC_FF_B (
    .I_WR_CLK(I_P_CLK), 
    .I_RD_CLK(I_A_CLK), 
    .I_WR_RESET_N(I_P_RESET_N), 
    .I_RD_RESET_N(I_A_RESET_N),
    .I_WR_EN(b_push), 
    .I_RD_EN(I_B_READY), 
    .I_WR_DATA(b_data_in), 
    .O_RD_DATA(b_data_out),
    .O_FIFO_ALMOST_FULL(b_almost_full), 
    .O_FIFO_FULL(b_full), 
    .O_FIFO_EMPTY(b_valid_n)
  );

  // AR FIFO
  BOS_ASYNC_GRAY_FIFO #(
    .BOS_PARA_DATA_W(BOS_PARA_AW_AR_DATA_WIDTH),
    .BOS_PARA_ADDR_W(`BOS_DEF_FIFO_DEPTH)
  ) u_ASYNC_FF_AR (
    .I_WR_CLK(I_A_CLK), 
    .I_RD_CLK(I_P_CLK), 
    .I_WR_RESET_N(I_A_RESET_N), 
    .I_RD_RESET_N(I_P_RESET_N),
    .I_WR_EN(I_AR_VALID), 
    .I_RD_EN(pop_read), 
    .I_WR_DATA({I_AR_ID, I_AR_ADDR}), 
    .O_RD_DATA(ar_data),
    .O_FIFO_ALMOST_EMPTY(ar_almost_empty), 
    .O_FIFO_FULL(ar_ready_n), 
    .O_FIFO_EMPTY(ar_empty)
  );

  // R FIFO
  BOS_ASYNC_GRAY_FIFO #(
    .BOS_PARA_DATA_W(BOS_PARA_R_DATA_WIDTH),
    .BOS_PARA_ADDR_W(`BOS_DEF_FIFO_DEPTH)
  ) u_ASYNC_FF_R (
    .I_WR_CLK(I_P_CLK), 
    .I_RD_CLK(I_A_CLK), 
    .I_WR_RESET_N(I_P_RESET_N), 
    .I_RD_RESET_N(I_A_RESET_N),
    .I_WR_EN(r_push), 
    .I_RD_EN(I_R_READY), 
    .I_WR_DATA(r_data_in), 
    .O_RD_DATA(r_data_out),
    .O_FIFO_ALMOST_FULL(r_almost_full), 
    .O_FIFO_FULL(r_full), 
    .O_FIFO_EMPTY(r_valid_n)
  );

  // --- Integrated Bridge Controller ---
  BOS_BRIDGE_CONTROLLER u_BRIDGE_CONTROLLER (
    .I_PCLK(I_P_CLK),
    .I_PRESETN(I_P_RESET_N),
    .O_PADDR(O_P_ADDR),
    .O_PWDATA(O_P_WDATA),
    .O_PSEL(O_P_SEL),
    .O_PENABLE(O_P_ENABLE),
    .O_PWRITE(O_P_WRITE),
    .O_PSTRB(O_P_STRB),
    .I_PREADY(I_P_READY),
    .I_PRDATA(I_P_RDATA),
    .I_PSLVERR(I_P_SLVERR),
    // Status Interface (Integrated Handler Logic)
    .I_AW_EMPTY(aw_empty), 
    .I_AW_ALMOST_EMPTY(aw_almost_empty),
    .I_W_EMPTY(w_empty),   
    .I_W_ALMOST_EMPTY(w_almost_empty),
    .I_B_FULL(b_full),     
    .I_B_ALMOST_FULL(b_almost_full),
    .I_AR_EMPTY(ar_empty), 
    .I_AR_ALMOST_EMPTY(ar_almost_empty),
    .I_R_FULL(r_full),     
    .I_R_ALMOST_FULL(r_almost_full),
    // Data & Control
    .I_AW_DATA(aw_data), 
    .I_W_DATA(w_data), 
    .I_AR_DATA(ar_data),
    .O_B_DATA(b_data_in), 
    .O_R_DATA(r_data_in),
    .O_POP_WRITE(pop_write), 
    .O_POP_READ(pop_read),
    .O_B_PUSH(b_push), 
    .O_R_PUSH(r_push),
    .O_STATE(state)
  );

  // Output mappings
  assign {O_B_ID, O_B_RESP} = b_data_out;
  assign {O_R_ID, O_R_DATA, O_R_RESP} = r_data_out;
  assign O_R_LAST   = O_R_VALID & I_R_READY;
  assign O_AW_READY = ~aw_ready_n;
  assign O_W_READY  = ~w_ready_n;
  assign O_AR_READY = ~ar_ready_n;
  assign O_B_VALID  = ~b_valid_n;
  assign O_R_VALID  = ~r_valid_n;

endmodule : AXI_TO_APB_BRIDGE