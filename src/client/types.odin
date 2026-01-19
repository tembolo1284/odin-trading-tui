package client

// ============================================================================
// Core types and constants for the matching engine client
// ============================================================================

MAX_SYMBOL_LENGTH :: 8

// Wire sizes (excluding 4-byte frame header)
NEW_ORDER_WIRE_SIZE   :: 27
CANCEL_WIRE_SIZE      :: 10
FLUSH_WIRE_SIZE       :: 2
ACK_WIRE_SIZE         :: 18
CANCEL_ACK_WIRE_SIZE  :: 18
TRADE_WIRE_SIZE       :: 34
TOP_OF_BOOK_WIRE_SIZE :: 20
REJECT_WIRE_SIZE      :: 19

// Protocol constants
MAGIC :: u8(0x4D) // 'M'

MSG_NEW_ORDER   :: u8('N')
MSG_CANCEL      :: u8('C')
MSG_FLUSH       :: u8('F')
MSG_ACK         :: u8('A')
MSG_CANCEL_ACK  :: u8('X')
MSG_TRADE       :: u8('T')
MSG_TOP_OF_BOOK :: u8('B')
MSG_REJECT      :: u8('R')

Side :: enum u8 {
    Buy  = 'B',
    Sell = 'S',
}

Reject_Reason :: enum u8 {
    Unknown_Symbol    = 1,
    Invalid_Quantity  = 2,
    Invalid_Price     = 3,
    Order_Not_Found   = 4,
    Duplicate_OrderId = 5,
    Pool_Exhausted    = 6,
    Unauthorized      = 7,
    Throttled         = 8,
    Book_Full         = 9,
    Invalid_OrderId   = 10,
}

Output_Type :: enum u8 {
    Ack         = 'A',
    Trade       = 'T',
    Top_Of_Book = 'B',
    Cancel_Ack  = 'X',
    Reject      = 'R',
}

// Decoded output message (union-style struct)
Output_Msg :: struct {
    typ:           Output_Type,
    symbol:        [MAX_SYMBOL_LENGTH]u8,
    
    // Ack / Cancel_Ack / Reject
    user_id:       u32,
    user_order_id: u32,
    
    // Trade
    buy_user_id:   u32,
    buy_order_id:  u32,
    sell_user_id:  u32,
    sell_order_id: u32,
    price:         u32,
    quantity:      u32,
    
    // Top of Book
    side:          Side,
    
    // Reject
    reason:        Reject_Reason,
}

// Stats for scenario tracking
Scenario_Stats :: struct {
    orders_sent:     u64,
    acks_received:   u64,
    trades_received: u64,
    cancels_sent:    u64,
    cancel_acks:     u64,
    rejects:         u64,
    start_time:      i64,
    end_time:        i64,
}
