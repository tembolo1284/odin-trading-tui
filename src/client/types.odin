package client

// ============================================================================
// Constants
// ============================================================================

MAX_SYMBOL_LENGTH     :: 16
MAX_SYMBOL_LENGTH_TOB :: 15  // Top-of-book uses 15 bytes for symbol

// Client ID ranges (matching C config)
CLIENT_ID_BROADCAST :: 0
CLIENT_ID_TCP_BASE  :: 0
CLIENT_ID_UDP_BASE  :: 0x80000000
CLIENT_ID_INVALID   :: 0xFFFFFFFF

// ============================================================================
// Enumerations (uint8 for wire compatibility)
// ============================================================================

Side :: enum u8 {
    Buy  = 'B',
    Sell = 'S',
}

Order_Type :: enum u8 {
    Market = 0,
    Limit  = 1,
}

Input_Msg_Type :: enum u8 {
    New_Order = 0,
    Cancel    = 1,
    Flush     = 2,
}

Output_Msg_Type :: enum u8 {
    Ack         = 0,
    Cancel_Ack  = 1,
    Trade       = 2,
    Top_Of_Book = 3,
}

Encoding_Type :: enum u8 {
    Auto   = 0,
    Binary = 1,
    Csv    = 2,
}

Transport_Type :: enum u8 {
    Auto = 0,
    Tcp  = 1,
    Udp  = 2,
}

Conn_State :: enum u8 {
    Disconnected = 0,
    Connecting   = 1,
    Connected    = 2,
    Error        = 3,
}

Client_Protocol :: enum u8 {
    Unknown = 0,
    Binary  = 1,
    Csv     = 2,
}

// ============================================================================
// Input Message Structures
// ============================================================================

// New Order Message (36 bytes)
// Layout:
//   0-3:   user_id
//   4-7:   user_order_id
//   8-11:  price
//   12-15: quantity
//   16:    side
//   17-19: _pad
//   20-35: symbol[16]
New_Order_Msg :: struct #packed {
    user_id:       u32,
    user_order_id: u32,
    price:         u32,
    quantity:      u32,
    side:          Side,
    _pad:          [3]u8,
    symbol:        [MAX_SYMBOL_LENGTH]u8,
}
#assert(size_of(New_Order_Msg) == 36)
#assert(offset_of(New_Order_Msg, symbol) == 20)

// Cancel Message (24 bytes)
Cancel_Msg :: struct #packed {
    user_id:       u32,
    user_order_id: u32,
    symbol:        [MAX_SYMBOL_LENGTH]u8,
}
#assert(size_of(Cancel_Msg) == 24)

// Flush Message (1 byte)
Flush_Msg :: struct #packed {
    _unused: u8,
}
#assert(size_of(Flush_Msg) == 1)

// Input Message - Tagged Union (40 bytes)
Input_Msg :: struct #packed {
    type: Input_Msg_Type,
    _pad: [3]u8,
    data: struct #raw_union {
        new_order: New_Order_Msg,
        cancel:    Cancel_Msg,
        flush:     Flush_Msg,
    },
}
#assert(size_of(Input_Msg) == 40)
#assert(offset_of(Input_Msg, data) == 4)

// ============================================================================
// Output Message Structures
// ============================================================================

// Acknowledgment Message (24 bytes)
Ack_Msg :: struct #packed {
    user_id:       u32,
    user_order_id: u32,
    symbol:        [MAX_SYMBOL_LENGTH]u8,
}
#assert(size_of(Ack_Msg) == 24)

// Cancel Acknowledgment Message (24 bytes)
Cancel_Ack_Msg :: struct #packed {
    user_id:       u32,
    user_order_id: u32,
    symbol:        [MAX_SYMBOL_LENGTH]u8,
}
#assert(size_of(Cancel_Ack_Msg) == 24)

// Trade Message (48 bytes)
Trade_Msg :: struct #packed {
    user_id_buy:       u32,
    user_order_id_buy: u32,
    user_id_sell:      u32,
    user_order_id_sell: u32,
    price:             u32,
    quantity:          u32,
    buy_client_id:     u32,
    sell_client_id:    u32,
    symbol:            [MAX_SYMBOL_LENGTH]u8,
}
#assert(size_of(Trade_Msg) == 48)
#assert(offset_of(Trade_Msg, symbol) == 32)

// Top of Book Message (24 bytes)
Top_Of_Book_Msg :: struct #packed {
    price:          u32,
    total_quantity: u32,
    side:           Side,
    symbol:         [MAX_SYMBOL_LENGTH_TOB]u8,
}
#assert(size_of(Top_Of_Book_Msg) == 24)

// Output Message - Tagged Union (52 bytes)
Output_Msg :: struct #packed {
    type: Output_Msg_Type,
    _pad: [3]u8,
    data: struct #raw_union {
        ack:         Ack_Msg,
        cancel_ack:  Cancel_Ack_Msg,
        trade:       Trade_Msg,
        top_of_book: Top_Of_Book_Msg,
    },
}
#assert(size_of(Output_Msg) == 52)
#assert(offset_of(Output_Msg, data) == 4)

// ============================================================================
// Envelope Structures (64 bytes, cache-aligned)
// ============================================================================

Udp_Client_Addr :: struct #packed {
    addr: u32,
    port: u16,
    _pad: u16,
}
#assert(size_of(Udp_Client_Addr) == 8)

Input_Msg_Envelope :: struct #packed {
    msg:         Input_Msg,
    client_id:   u32,
    client_addr: Udp_Client_Addr,
    _pad:        u32,
    sequence:    u64,
}
#assert(size_of(Input_Msg_Envelope) == 64)

Output_Msg_Envelope :: struct #packed {
    msg:       Output_Msg,
    client_id: u32,
    sequence:  u64,
}
#assert(size_of(Output_Msg_Envelope) == 64)

// ============================================================================
// Validation Helpers
// ============================================================================

side_is_valid :: proc(side: Side) -> bool {
    return side == .Buy || side == .Sell
}

input_msg_type_is_valid :: proc(t: Input_Msg_Type) -> bool {
    return t <= .Flush
}

output_msg_type_is_valid :: proc(t: Output_Msg_Type) -> bool {
    return t <= .Top_Of_Book
}

client_id_is_udp :: proc(client_id: u32) -> bool {
    return client_id > CLIENT_ID_UDP_BASE
}

client_id_is_tcp :: proc(client_id: u32) -> bool {
    return client_id > 0 && client_id <= CLIENT_ID_UDP_BASE
}

top_of_book_is_eliminated :: proc(msg: ^Top_Of_Book_Msg) -> bool {
    return msg.price == 0 && msg.total_quantity == 0
}

// ============================================================================
// Symbol Helpers
// ============================================================================

copy_symbol :: proc(dest: []u8, src: string) {
    n := min(len(dest) - 1, len(src))
    for i in 0..<n {
        dest[i] = src[i]
    }
    for i in n..<len(dest) {
        dest[i] = 0
    }
}

get_symbol :: proc(sym: []u8) -> string {
    for i in 0..<len(sym) {
        if sym[i] == 0 {
            return string(sym[:i])
        }
    }
    return string(sym[:])
}

// ============================================================================
// Message Constructors
// ============================================================================

make_new_order :: proc(
    user_id: u32,
    user_order_id: u32,
    symbol: string,
    price: u32,
    quantity: u32,
    side: Side,
) -> Input_Msg {
    msg: Input_Msg
    msg.type = .New_Order
    msg._pad = {}
    msg.data.new_order.user_id = user_id
    msg.data.new_order.user_order_id = user_order_id
    msg.data.new_order.price = price
    msg.data.new_order.quantity = quantity
    msg.data.new_order.side = side
    msg.data.new_order._pad = {}
    copy_symbol(msg.data.new_order.symbol[:], symbol)
    return msg
}

make_cancel :: proc(
    user_id: u32,
    user_order_id: u32,
    symbol: string,
) -> Input_Msg {
    msg: Input_Msg
    msg.type = .Cancel
    msg._pad = {}
    msg.data.cancel.user_id = user_id
    msg.data.cancel.user_order_id = user_order_id
    copy_symbol(msg.data.cancel.symbol[:], symbol)
    return msg
}

make_flush :: proc() -> Input_Msg {
    msg: Input_Msg
    msg.type = .Flush
    msg._pad = {}
    msg.data.flush._unused = 0
    return msg
}

// ============================================================================
// Message Type Names
// ============================================================================

input_msg_type_name :: proc(t: Input_Msg_Type) -> string {
    switch t {
    case .New_Order: return "NEW_ORDER"
    case .Cancel:    return "CANCEL"
    case .Flush:     return "FLUSH"
    }
    return "UNKNOWN"
}

output_msg_type_name :: proc(t: Output_Msg_Type) -> string {
    switch t {
    case .Ack:         return "ACK"
    case .Cancel_Ack:  return "CANCEL_ACK"
    case .Trade:       return "TRADE"
    case .Top_Of_Book: return "TOP_OF_BOOK"
    }
    return "UNKNOWN"
}

side_char :: proc(side: Side) -> u8 {
    return u8(side)
}
