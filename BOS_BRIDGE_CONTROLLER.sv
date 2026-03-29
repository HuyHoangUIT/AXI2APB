//---------------------------------------------------------------------- 
// Company: BOS Semiconductors
// Author: Nguyen Hoan Khanh, Nguyen Ngoc Huy Hoang
//  Description: This controller is used to drive data from FIFO to APB slave.
//----------------------------------------------------------------------

`timescale 1ns / 1ps

module BOS_BRIDGE_CONTROLLER
#(
  localparam BOS_PARA_AWR_DATA_WIDTH  = `BOS_DEF_ADDR_WIDTH + `BOS_DEF_ADDR_ID_WIDTH,
  localparam BOS_PARA_W_DATA_WIDTH    = `BOS_DEF_DATA_WIDTH + `BOS_DEF_STRB_WIDTH,
  localparam BOS_PARA_B_DATA_WIDTH    = `BOS_DEF_ADDR_ID_WIDTH + 2,
  localparam BOS_PARA_R_DATA_WIDTH    = `BOS_DEF_DATA_WIDTH + `BOS_DEF_STRB_WIDTH + 2
)
(
  // --- System signals ---
  input                                        I_PCLK,
  input                                        I_PRESETN,

  // --- To APB slave ---
  output logic [`BOS_DEF_ADDR_WIDTH-1:0]       O_PADDR,
  output logic [`BOS_DEF_DATA_WIDTH-1:0]       O_PWDATA,
  output logic                                 O_PSEL,
  output logic                                 O_PENABLE,
  output logic                                 O_PWRITE,
  output logic [`BOS_DEF_STRB_WIDTH-1:0]       O_PSTRB,

  // --- From APB slave ---
  input                                        I_PREADY,
  input        [`BOS_DEF_DATA_WIDTH-1:0]       I_PRDATA,
  input                                        I_PSLVERR,

  // --- FIFO Status Interface ---
  input                                        I_AW_EMPTY, 
  input                                        I_AW_ALMOST_EMPTY,
  input                                        I_W_EMPTY,  
  input                                        I_W_ALMOST_EMPTY,
  input                                        I_B_FULL,   
  input                                        I_B_ALMOST_FULL,
  input                                        I_AR_EMPTY, 
  input                                        I_AR_ALMOST_EMPTY,
  input                                        I_R_FULL,   
  input                                        I_R_ALMOST_FULL,

  // --- Data Interface ---
  input        [BOS_PARA_AWR_DATA_WIDTH-1:0]   I_AW_DATA,
  input        [BOS_PARA_W_DATA_WIDTH-1:0]     I_W_DATA,
  input        [BOS_PARA_AWR_DATA_WIDTH-1:0]   I_AR_DATA,
  output logic [BOS_PARA_B_DATA_WIDTH-1:0]     O_B_DATA,
  output logic [BOS_PARA_R_DATA_WIDTH-1:0]     O_R_DATA,

  // --- FIFO Control Signals ---
  output logic                                 O_POP_WRITE,
  output logic                                 O_POP_READ,
  output logic                                 O_B_PUSH,
  output logic                                 O_R_PUSH,

  // --- Monitor ---
  output state_t                               O_STATE
);

  
  state_t r_curr_state, r_next_state;
  logic   w_write_ready, w_read_ready;

  // --- BLOCK 1: State Transition (Sequential) ---
  always_ff @(posedge I_PCLK or negedge I_PRESETN) begin
    if (~I_PRESETN) begin
      r_curr_state <= ST_IDLE;
    end else begin
      r_curr_state <= r_next_state;
    end
  end

  // --- BLOCK 2: Next State Logic (Combinational) ---
  always_comb begin
    r_next_state = r_curr_state;
    
    case (r_curr_state)
      ST_IDLE: begin
        if (w_write_ready)      r_next_state = ST_SETUP_WRITE;
        else if (w_read_ready)  r_next_state = ST_SETUP_READ;
        else                    r_next_state = ST_IDLE;
      end

      ST_SETUP_WRITE: begin
        r_next_state = ST_ACCESS_WRITE;
      end
      
      ST_SETUP_READ: begin
        r_next_state = ST_ACCESS_READ;
      end

      ST_ACCESS_WRITE: begin
        if (I_PREADY) begin
          if (w_read_ready)       r_next_state = ST_SETUP_READ;
          else if (w_write_ready) r_next_state = ST_SETUP_WRITE;
          else                    r_next_state = ST_IDLE;
        end else begin
          r_next_state = ST_ACCESS_WRITE;
        end
      end

      ST_ACCESS_READ: begin
        if (I_PREADY) begin
          if (w_write_ready)      r_next_state = ST_SETUP_WRITE;
          else if (w_read_ready)  r_next_state = ST_SETUP_READ;
          else                    r_next_state = ST_IDLE;
        end else begin
          r_next_state = ST_ACCESS_READ;
        end
      end

      default: begin
        r_next_state = ST_IDLE;
      end
    endcase
  end

  // --- BLOCK 4: Output Logic (Combinational) ---
  always_comb begin

    case (r_curr_state)
      ST_IDLE: begin
         O_PSEL      = 1'b0;
         O_PWRITE    = 1'b0;
         O_PENABLE   = 1'b0;
         O_PADDR     = 'h0; 
         O_PWDATA    = 'h0; 
         O_PSTRB     = 'h0;  
      end

      ST_SETUP_WRITE: begin
        O_PSEL    = 1'b1;
        O_PWRITE  = 1'b1;
        O_PENABLE = 1'b0;
        O_PADDR   = I_AW_DATA[`BOS_DEF_ADDR_WIDTH-1 : 0];
        O_PWDATA  = I_W_DATA[BOS_PARA_W_DATA_WIDTH-1 : `BOS_DEF_STRB_WIDTH];
        O_PSTRB   = I_W_DATA[`BOS_DEF_STRB_WIDTH-1 : 0];
        O_B_DATA  = {I_AW_DATA[BOS_PARA_AWR_DATA_WIDTH-1 : `BOS_DEF_ADDR_WIDTH], I_PSLVERR, 1'b0};
      end

      ST_ACCESS_WRITE: begin
        O_PSEL    = 1'b1;
        O_PWRITE  = 1'b1;
        O_PENABLE = 1'b1;
        O_PADDR   = I_AW_DATA[`BOS_DEF_ADDR_WIDTH-1 : 0];
        O_PWDATA  = I_W_DATA[BOS_PARA_W_DATA_WIDTH-1 : `BOS_DEF_STRB_WIDTH];
        O_PSTRB   = I_W_DATA[`BOS_DEF_STRB_WIDTH-1 : 0];
        O_B_DATA  = {I_AW_DATA[BOS_PARA_AWR_DATA_WIDTH-1 : `BOS_DEF_ADDR_WIDTH], I_PSLVERR, 1'b0};
      end

      ST_SETUP_READ: begin
        O_PSEL    = 1'b1;
        O_PWRITE  = 1'b0;
        O_PENABLE = 1'b0;
        O_PADDR   = I_AR_DATA[`BOS_DEF_ADDR_WIDTH-1 : 0];
        O_R_DATA  = I_PRDATA; 
      end

      ST_ACCESS_READ: begin
        O_PSEL    = 1'b1;
        O_PWRITE  = 1'b0;
        O_PENABLE = 1'b1;
        O_PADDR   = I_AR_DATA[`BOS_DEF_ADDR_WIDTH-1 : 0];
        O_R_DATA  = I_PRDATA;
      end
      
      default: begin
        O_PSEL      = 1'b0;
        O_PWRITE    = 1'b0;
        O_PENABLE   = 1'b0;
        O_PADDR     = 'h0;
        O_PWDATA    = 'h0;
        O_PSTRB     = 'h0;
      end
    endcase
  end
  
  assign w_write_ready = ~(I_AW_EMPTY | I_W_EMPTY | I_B_FULL | ((I_B_ALMOST_FULL | I_W_ALMOST_EMPTY | I_AW_ALMOST_EMPTY) & (r_curr_state == ST_ACCESS_WRITE)));
  assign O_B_PUSH      = (r_curr_state == ST_ACCESS_WRITE) & I_PREADY;
  assign O_POP_WRITE   = (r_curr_state == ST_ACCESS_WRITE) & I_PREADY;
  
  assign w_read_ready  = ~(I_AR_EMPTY | I_R_FULL | ((I_R_ALMOST_FULL | I_AR_ALMOST_EMPTY) & (r_curr_state == ST_ACCESS_READ)));
  assign O_R_PUSH      = (r_curr_state == ST_ACCESS_READ)  & I_PREADY;
  assign O_POP_READ    = (r_curr_state == ST_ACCESS_READ)  & I_PREADY;
  
  assign O_STATE = r_curr_state;
  assign O_B_DATA = {I_AW_DATA[BOS_PARA_AWR_DATA_WIDTH - 1 -: 2], I_PSLVERR, 1'b0};
  assign O_R_DATA = {I_AR_DATA[BOS_PARA_AWR_DATA_WIDTH - 1 -: 2], I_PRDATA, I_PSLVERR, 1'b0};

endmodule: BOS_BRIDGE_CONTROLLER