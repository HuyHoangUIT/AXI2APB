`timescale 1ns/1ps
module BOS_ASYNC_GRAY_FIFO
#(
  parameter int BOS_PARA_DATA_W = 32,
  parameter int BOS_PARA_ADDR_W = 4    // FIFO depth = 2^ADDR_W
)
(
  input                           I_WR_CLK,
  input                           I_RD_CLK,
  input                           I_WR_RESET_N,   // active-low reset
  input                           I_RD_RESET_N,   // active-low reset

  input                           I_WR_EN,
  input                           I_RD_EN,
  input   [BOS_PARA_DATA_W-1:0]   I_WR_DATA,
  output  [BOS_PARA_DATA_W-1:0]   O_RD_DATA,

  output logic                    O_FIFO_ALMOST_FULL,
  output logic                    O_FIFO_ALMOST_EMPTY,
  output logic                    O_FIFO_FULL,
  output logic                    O_FIFO_EMPTY
);

  localparam int BOS_PARA_FIFO_DEPTH = (1 << BOS_PARA_ADDR_W);
  localparam int BOS_PARA_PTR_W      = BOS_PARA_ADDR_W + 1;

  // ============================================================
  // Memory array
  // ============================================================
  logic [BOS_PARA_DATA_W-1:0] mem [0:BOS_PARA_FIFO_DEPTH-1];

  // ============================================================
  // Local binary pointers
  // write_cnt[N:0], read_cnt[N:0]
  // ============================================================
  logic [BOS_PARA_PTR_W-1:0] write_cnt;
  logic [BOS_PARA_PTR_W-1:0] read_cnt;

  logic [BOS_PARA_PTR_W-1:0] write_cnt_nxt;
  logic [BOS_PARA_PTR_W-1:0] read_cnt_nxt;

  // ============================================================
  // Gray pointers generated from local binary pointers
  // ============================================================
  logic [BOS_PARA_PTR_W-1:0] write_cnt_gray;
  logic [BOS_PARA_PTR_W-1:0] read_cnt_gray;

  // ============================================================
  // Crossing Gray pointers through 2FF synchronizers
  // ============================================================
  logic [BOS_PARA_PTR_W-1:0] read_cnt_gray_sync_ff1;
  logic [BOS_PARA_PTR_W-1:0] read_cnt_gray_sync_ff2;

  logic [BOS_PARA_PTR_W-1:0] write_cnt_gray_sync_ff1;
  logic [BOS_PARA_PTR_W-1:0] write_cnt_gray_sync_ff2;

  // ============================================================
  // Gray -> Binary after synchronization
  // ============================================================
  logic [BOS_PARA_PTR_W-1:0] read_cnt_sync_bin;
  logic [BOS_PARA_PTR_W-1:0] write_cnt_sync_bin;

  // ============================================================
  // Internal enables
  // ============================================================
  logic write_en;
  logic read_en;

  assign write_en = I_WR_EN & ~O_FIFO_FULL;
  assign read_en  = I_RD_EN & ~O_FIFO_EMPTY;

  // ============================================================
  // Next pointer logic
  // matches the +1 mux structure in your diagram
  // ============================================================
  assign write_cnt_nxt = write_cnt + {{(BOS_PARA_PTR_W-1){1'b0}}, write_en};
  assign read_cnt_nxt  = read_cnt  + {{(BOS_PARA_PTR_W-1){1'b0}}, read_en};
// ============================================================
  // Bin2Gray blocks
  // ============================================================
  assign write_cnt_gray = write_cnt ^ (write_cnt >> 1);
  assign read_cnt_gray  = read_cnt  ^ (read_cnt  >> 1);

  // ============================================================
  // 2FF synchronizer: read pointer Gray -> write clock domain
  // ============================================================
  always_ff @(posedge I_WR_CLK or negedge I_WR_RESET_N) begin
    if (!I_WR_RESET_N) begin
      read_cnt_gray_sync_ff1 <= '0;
      read_cnt_gray_sync_ff2 <= '0;
    end
    else begin
      read_cnt_gray_sync_ff1 <= read_cnt_gray;
      read_cnt_gray_sync_ff2 <= read_cnt_gray_sync_ff1;
    end
  end

  // ============================================================
  // 2FF synchronizer: write pointer Gray -> read clock domain
  // ============================================================
  always_ff @(posedge I_RD_CLK or negedge I_RD_RESET_N) begin
    if (!I_RD_RESET_N) begin
      write_cnt_gray_sync_ff1 <= '0;
      write_cnt_gray_sync_ff2 <= '0;
    end
    else begin
      write_cnt_gray_sync_ff1 <= write_cnt_gray;
      write_cnt_gray_sync_ff2 <= write_cnt_gray_sync_ff1;
    end
  end

  // ============================================================
  // Gray2Bin blocks
  // ============================================================
  genvar i;
  generate
    for (i = 0; i < BOS_PARA_DATA_W; i++) begin  
      assign write_cnt_sync_bin [i] = ^write_cnt_gray_sync_ff2 [BOS_PARA_DATA_W-1:i];
      assign read_cnt_sync_bin  [i] = ^read_cnt_gray_sync_ff2  [BOS_PARA_DATA_W-1:i];
    end
  endgenerate

  // ============================================================
  // FIFO FULL generation
  // Based on your diagram:
  // - low ADDR bits equal
  // - MSB different
  //
  // write_cnt[N-1:0] == read_cnt_sync_bin[N-1:0]
  // write_cnt[N]     != read_cnt_sync_bin[N]
  // ============================================================
  always_comb begin
    O_FIFO_FULL =
      (write_cnt[BOS_PARA_PTR_W-2:0] == read_cnt_sync_bin[BOS_PARA_PTR_W-2:0]) &&
      (write_cnt[BOS_PARA_PTR_W-1]     != read_cnt_sync_bin[BOS_PARA_PTR_W-1]);
    O_FIFO_ALMOST_FULL = 
      (write_cnt_nxt[BOS_PARA_PTR_W-2:0] == read_cnt_sync_bin[BOS_PARA_PTR_W-2:0]) &&
      (write_cnt_nxt[BOS_PARA_PTR_W-1]     != read_cnt_sync_bin[BOS_PARA_PTR_W-1]);
  end

  // ============================================================
  // FIFO EMPTY generation
  // Based on your diagram:
  // read_cnt == synchronized write_cnt
  // ============================================================
  always_comb begin
    O_FIFO_EMPTY        = (read_cnt     == write_cnt_sync_bin);
    O_FIFO_ALMOST_EMPTY = (read_cnt_nxt == write_cnt_sync_bin);
  end

  // ============================================================
  // Write domain logic
  // - update write pointer
  // - write memory when write_en asserted
// ============================================================
  always_ff @(posedge I_WR_CLK or negedge I_WR_RESET_N) begin
    if (!I_WR_RESET_N) begin
      write_cnt <= '0;
    end
    else begin
      if (write_en) begin
        mem[write_cnt[BOS_PARA_ADDR_W-1:0]] <= I_WR_DATA;
        write_cnt <= write_cnt_nxt;
      end
    end
  end

  // ============================================================
  // Read domain logic
  // update read pointer
  // ============================================================
  always_ff @(posedge I_RD_CLK or negedge I_RD_RESET_N) begin
    if (!I_RD_RESET_N) begin
      read_cnt <= '0;
    end
    else begin
      if (read_en) begin
        read_cnt <= read_cnt_nxt;
      end
    end
  end

  // ============================================================
  // Read data path
  // MUX architecture in your figure => combinational read
  // ============================================================
  assign O_RD_DATA = mem[read_cnt[BOS_PARA_ADDR_W-1:0]];

endmodule : BOS_ASYNC_GRAY_FIFO
