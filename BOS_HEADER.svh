//---------------------------------------------------------------------- 
// Company: BOS Semiconductors
// Author: Nguyen Hoan Khanh
// Description: There are definitions for all components in the bridge.
//----------------------------------------------------------------------

`define BOS_DEF_DATA_WIDTH 32
`define BOS_DEF_ADDR_ID_WIDTH 2
`define BOS_DEF_ADDR_WIDTH 16
`define BOS_DEF_STRB_WIDTH 4
`define BOS_DEF_FIFO_DEPTH 4
`define BOS_DEF_READ_HANDLER_WIDTH 36
`define BOS_DEF_WRITE_HANDLER_WIDTH 4

typedef enum logic [2 : 0] {
    ST_IDLE         = 3'b000,
    ST_SETUP_WRITE  = 3'b001,
    ST_SETUP_READ   = 3'b010,
    ST_ACCESS_WRITE = 3'b011,
    ST_ACCESS_READ  = 3'b100
  } state_t;