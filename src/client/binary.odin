package client

// =============================================================================
// Binary Protocol
//
// Wire-format structures matching C's protocol/binary/binary_protocol.h
// All multi-byte integers are network byte order (big-endian).
// =============================================================================

import "core:mem"
import "core:intrinsics"

// =============================================================================
// Binary Message Types
// =============================================================================

BINARY_MSG_NEW_ORDER   :: 'N'
BINARY_MSG_CANCEL      :: 'C'
BINARY_MSG_FLUSH       :: 'F'
BINARY_MSG_ACK         :: 'A'
BINARY_MSG_CANCEL_ACK  :: 'X'
BINARY_MSG_TRADE       :: 'T'
BINARY_MSG_TOP_OF_BOOK :: 'B'

// =============================================================================
// Wire Format Structures (packed, matching C exactly)
// =============================================================================

// Binary New Order - 27 bytes
Binary_New_Order :: struct #packed {
    magic:         u8,                     // 0x4D
    msg_type:      u8,                     // 'N'
    user_id:       u32be,                  // Network byte order
    symbol:        [BINARY_SYMBOL_LEN]u8,
    price:         u32be,
    quantity:      u32be,
    side:          u8,                     // 'B' or 'S'
    user_order_id: u32be,
}
#assert(size_of(Binary_New_Order) == 27)

// Binary Cancel - 10 bytes
Binary_Cancel :: struct #packed {
    magic:         u8,
    msg_type:      u8,
    user_id:       u32be,
    user_order_id: u32be,
}
#assert(size_of(Binary_Cancel) == 10)

// Binary Flush - 2 bytes
Binary_Flush :: struct #packed {
    magic:    u8,
    msg_type: u8,
}
#assert(size_of(Binary_Flush) == 2)

// Binary Ack - 18 bytes
Binary_Ack :: struct #packed {
    magic:         u8,
    msg_type:      u8,
    symbol:        [BINARY_SYMBOL_LEN]u8,
    user_id:       u32be,
    user_order_id: u32be,
}
#assert(size_of(Binary_Ack) == 18)

// Binary Cancel Ack - 18 bytes
Binary_Cancel_Ack :: struct #packed {
    magic:         u8,
    msg_type:      u8,
    symbol:        [BINARY_SYMBOL_LEN]u8,
    user_id:       u32be,
    user_order_id: u32be,
}
#assert(size_of(Binary_Cancel_Ack) == 18)

// Binary Trade - 34 bytes
Binary_Trade :: struct #packed {
    magic:              u8,
    msg_type:           u8,
    symbol:             [BINARY_SYMBOL_LEN]u8,
    user_id_buy:        u32be,
    user_order_id_buy:  u32be,
    user_id_sell:       u32be,
    user_order_id_sell: u32be,
    price:              u32be,
    quantity:           u32be,
}
#assert(size_of(Binary_Trade) == 34)

// Binary Top of Book - 19 bytes
Binary_Top_Of_Book :: struct #packed {
    magic:    u8,
    msg_type: u8,
    symbol:   [BINARY_SYMBOL_LEN]u8,
    side:     u8,
    price:    u32be,
    quantity: u32be,
}
#assert(size_of(Binary_Top_Of_Book) == 19)

// =============================================================================
// Encoding Functions
// =============================================================================

// Encode a new order message to binary format
// Returns number of bytes written, or 0 on error
binary_encode_new_order :: proc(
    buffer: []u8,
    user_id: u32,
    symbol: string,
    price: u32,
    quantity: u32,
    side: Side,
    order_id: u32,
) -> int {
    if len(buffer) < size_of(Binary_New_Order) {
        return 0
    }

    msg := cast(^Binary_New_Order)raw_data(buffer)
    msg.magic = BINARY_MAGIC
    msg.msg_type = BINARY_MSG_NEW_ORDER
    msg.user_id = u32be(user_id)
    msg.price = u32be(price)
    msg.quantity = u32be(quantity)
    msg.side = side_to_char(side)
    msg.user_order_id = u32be(order_id)

    // Copy symbol with null padding
    for i in 0..<BINARY_SYMBOL_LEN {
        if i < len(symbol) {
            msg.symbol[i] = symbol[i]
        } else {
            msg.symbol[i] = 0
        }
    }

    return size_of(Binary_New_Order)
}

// Encode a cancel message to binary format
binary_encode_cancel :: proc(buffer: []u8, user_id: u32, order_id: u32) -> int {
    if len(buffer) < size_of(Binary_Cancel) {
        return 0
    }

    msg := cast(^Binary_Cancel)raw_data(buffer)
    msg.magic = BINARY_MAGIC
    msg.msg_type = BINARY_MSG_CANCEL
    msg.user_id = u32be(user_id)
    msg.user_order_id = u32be(order_id)

    return size_of(Binary_Cancel)
}

// Encode a flush message to binary format
binary_encode_flush :: proc(buffer: []u8) -> int {
    if len(buffer) < size_of(Binary_Flush) {
        return 0
    }

    msg := cast(^Binary_Flush)raw_data(buffer)
    msg.magic = BINARY_MAGIC
    msg.msg_type = BINARY_MSG_FLUSH

    return size_of(Binary_Flush)
}

// =============================================================================
// Decoding Functions
// =============================================================================

// Check if data starts with binary protocol magic
is_binary_message :: proc(data: []u8) -> bool {
    if len(data) < 2 {
        return false
    }
    return data[0] == BINARY_MAGIC
}

// Get expected size for a binary message type
binary_message_size :: proc(msg_type: u8) -> int {
    switch msg_type {
    case BINARY_MSG_NEW_ORDER:   return size_of(Binary_New_Order)
    case BINARY_MSG_CANCEL:      return size_of(Binary_Cancel)
    case BINARY_MSG_FLUSH:       return size_of(Binary_Flush)
    case BINARY_MSG_ACK:         return size_of(Binary_Ack)
    case BINARY_MSG_CANCEL_ACK:  return size_of(Binary_Cancel_Ack)
    case BINARY_MSG_TRADE:       return size_of(Binary_Trade)
    case BINARY_MSG_TOP_OF_BOOK: return size_of(Binary_Top_Of_Book)
    case:                        return 0
    }
}

// Decode a binary response message into Output_Msg
binary_decode_response :: proc(data: []u8, msg: ^Output_Msg) -> bool {
    if len(data) < 2 || data[0] != BINARY_MAGIC {
        return false
    }

    msg_type := data[1]

    switch msg_type {
    case BINARY_MSG_ACK:
        if len(data) < size_of(Binary_Ack) do return false
        ack := cast(^Binary_Ack)raw_data(data)

        msg.type = .Ack
        ack_data: Ack_Msg
        ack_data.user_id = u32(ack.user_id)
        ack_data.user_order_id = u32(ack.user_order_id)
        // Copy symbol
        for i in 0..<BINARY_SYMBOL_LEN {
            ack_data.symbol[i] = ack.symbol[i]
        }
        msg.data = ack_data
        return true

    case BINARY_MSG_CANCEL_ACK:
        if len(data) < size_of(Binary_Cancel_Ack) do return false
        cack := cast(^Binary_Cancel_Ack)raw_data(data)

        msg.type = .Cancel_Ack
        cack_data: Cancel_Ack_Msg
        cack_data.user_id = u32(cack.user_id)
        cack_data.user_order_id = u32(cack.user_order_id)
        for i in 0..<BINARY_SYMBOL_LEN {
            cack_data.symbol[i] = cack.symbol[i]
        }
        msg.data = cack_data
        return true

    case BINARY_MSG_TRADE:
        if len(data) < size_of(Binary_Trade) do return false
        trade := cast(^Binary_Trade)raw_data(data)

        msg.type = .Trade
        trade_data: Trade_Msg
        trade_data.user_id_buy = u32(trade.user_id_buy)
        trade_data.user_order_id_buy = u32(trade.user_order_id_buy)
        trade_data.user_id_sell = u32(trade.user_id_sell)
        trade_data.user_order_id_sell = u32(trade.user_order_id_sell)
        trade_data.price = u32(trade.price)
        trade_data.quantity = u32(trade.quantity)
        for i in 0..<BINARY_SYMBOL_LEN {
            trade_data.symbol[i] = trade.symbol[i]
        }
        msg.data = trade_data
        return true

    case BINARY_MSG_TOP_OF_BOOK:
        if len(data) < size_of(Binary_Top_Of_Book) do return false
        tob := cast(^Binary_Top_Of_Book)raw_data(data)

        msg.type = .Top_Of_Book
        tob_data: Top_Of_Book_Msg
        tob_data.price = u32(tob.price)
        tob_data.total_quantity = u32(tob.quantity)
        tob_data.side, _ = side_from_char(tob.side)
        for i in 0..<BINARY_SYMBOL_LEN {
            if i < len(tob_data.symbol) {
                tob_data.symbol[i] = tob.symbol[i]
            }
        }
        msg.data = tob_data
        return true

    case:
        return false
    }
}
