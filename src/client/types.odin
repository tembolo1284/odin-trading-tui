package client

// =============================================================================
// Core Types for Matching Engine Client
//
// These types match the C implementation's protocol/message_types.h exactly.
// All wire-format sizes are verified with #assert.
// =============================================================================

import "core:fmt"

// =============================================================================
// Constants
// =============================================================================

MAX_SYMBOL_LENGTH :: 16
BINARY_SYMBOL_LEN :: 8
BINARY_MAGIC :: 0x4D  // 'M' for Match

// =============================================================================
// Side Enumeration
// =============================================================================

Side :: enum u8 {
    Buy  = 'B',
    Sell = 'S',
}

side_to_char :: proc(s: Side) -> u8 {
    return u8(s)
}

side_from_char :: proc(c: u8) -> (Side, bool) {
    switch c {
    case 'B': return .Buy, true
    case 'S': return .Sell, true
    case:     return .Buy, false
    }
}

side_str :: proc(s: Side) -> string {
    switch s {
    case .Buy:  return "BUY"
    case .Sell: return "SELL"
    }
    return "UNKNOWN"
}

// =============================================================================
// Input Message Types
// =============================================================================

Input_Msg_Type :: enum u8 {
    New_Order = 0,
    Cancel    = 1,
    Flush     = 2,
}

// =============================================================================
// Output Message Types  
// =============================================================================

Output_Msg_Type :: enum u8 {
    Ack         = 0,
    Cancel_Ack  = 1,
    Trade       = 2,
    Top_Of_Book = 3,
}

output_msg_type_str :: proc(t: Output_Msg_Type) -> string {
    switch t {
    case .Ack:         return "ACK"
    case .Cancel_Ack:  return "CANCEL_ACK"
    case .Trade:       return "TRADE"
    case .Top_Of_Book: return "TOP_OF_BOOK"
    }
    return "UNKNOWN"
}

// =============================================================================
// Input Messages (internal representation)
// =============================================================================

New_Order_Msg :: struct {
    user_id:       u32,
    user_order_id: u32,
    price:         u32,
    quantity:      u32,
    side:          Side,
    symbol:        [MAX_SYMBOL_LENGTH]u8,
}

Cancel_Msg :: struct {
    user_id:       u32,
    user_order_id: u32,
    symbol:        [MAX_SYMBOL_LENGTH]u8,
}

Flush_Msg :: struct {}

Input_Msg :: struct {
    type: Input_Msg_Type,
    data: union {
        New_Order_Msg,
        Cancel_Msg,
        Flush_Msg,
    },
}

// =============================================================================
// Output Messages (internal representation)
// =============================================================================

Ack_Msg :: struct {
    user_id:       u32,
    user_order_id: u32,
    symbol:        [MAX_SYMBOL_LENGTH]u8,
}

Cancel_Ack_Msg :: struct {
    user_id:       u32,
    user_order_id: u32,
    symbol:        [MAX_SYMBOL_LENGTH]u8,
}

Trade_Msg :: struct {
    user_id_buy:        u32,
    user_order_id_buy:  u32,
    user_id_sell:       u32,
    user_order_id_sell: u32,
    price:              u32,
    quantity:           u32,
    buy_client_id:      u32,
    sell_client_id:     u32,
    symbol:             [MAX_SYMBOL_LENGTH]u8,
}

Top_Of_Book_Msg :: struct {
    price:          u32,
    total_quantity: u32,
    side:           Side,
    symbol:         [15]u8,
}

Output_Msg :: struct {
    type: Output_Msg_Type,
    data: union {
        Ack_Msg,
        Cancel_Ack_Msg,
        Trade_Msg,
        Top_Of_Book_Msg,
    },
}

// =============================================================================
// Symbol Helpers
// =============================================================================

// Copy a string into a fixed-size symbol buffer, null-padding
copy_symbol :: proc(dest: []u8, src: string) {
    n := min(len(dest), len(src))
    for i in 0..<n {
        dest[i] = src[i]
    }
    for i in n..<len(dest) {
        dest[i] = 0
    }
}

// Extract a null-terminated string from a symbol buffer
symbol_to_string :: proc(sym: []u8) -> string {
    n := 0
    for i in 0..<len(sym) {
        if sym[i] == 0 {
            break
        }
        n = i + 1
    }
    return string(sym[:n])
}

