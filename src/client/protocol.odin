package client

import "core:mem"

// ============================================================================
// Binary protocol encoding/decoding
// ============================================================================

// ============================================================================
// Symbol helpers
// ============================================================================

write_symbol :: proc(dst: []u8, sym: string) {
    n := min(len(dst), len(sym))
    for i in 0..<n {
        dst[i] = sym[i]
    }
    for i in n..<len(dst) {
        dst[i] = 0
    }
}

symbol_to_string :: proc(sym: []u8) -> string {
    for i in 0..<len(sym) {
        if sym[i] == 0 {
            return string(sym[:i])
        }
    }
    return string(sym[:])
}

// ============================================================================
// Encode input messages
// ============================================================================

encode_new_order :: proc(
    buf:           []u8,
    user_id:       u32,
    symbol:        string,
    price:         u32,
    qty:           u32,
    side:          Side,
    user_order_id: u32,
) -> (int, bool) {
    if len(buf) < NEW_ORDER_WIRE_SIZE {
        return 0, false
    }
    if qty == 0 || len(symbol) == 0 {
        return 0, false
    }
    
    pos := 0
    
    buf[pos] = MAGIC
    pos += 1
    buf[pos] = MSG_NEW_ORDER
    pos += 1
    
    write_u32_be(buf[pos:], user_id)
    pos += 4
    
    write_symbol(buf[pos:pos+MAX_SYMBOL_LENGTH], symbol)
    pos += MAX_SYMBOL_LENGTH
    
    write_u32_be(buf[pos:], price)
    pos += 4
    
    write_u32_be(buf[pos:], qty)
    pos += 4
    
    buf[pos] = u8(side)
    pos += 1
    
    write_u32_be(buf[pos:], user_order_id)
    pos += 4
    
    return pos, pos == NEW_ORDER_WIRE_SIZE
}

encode_cancel :: proc(
    buf:           []u8,
    user_id:       u32,
    user_order_id: u32,
) -> (int, bool) {
    if len(buf) < CANCEL_WIRE_SIZE {
        return 0, false
    }
    
    pos := 0
    
    buf[pos] = MAGIC
    pos += 1
    buf[pos] = MSG_CANCEL
    pos += 1
    
    write_u32_be(buf[pos:], user_id)
    pos += 4
    
    write_u32_be(buf[pos:], user_order_id)
    pos += 4
    
    return pos, pos == CANCEL_WIRE_SIZE
}

encode_flush :: proc(buf: []u8) -> (int, bool) {
    if len(buf) < FLUSH_WIRE_SIZE {
        return 0, false
    }
    
    buf[0] = MAGIC
    buf[1] = MSG_FLUSH
    
    return FLUSH_WIRE_SIZE, true
}

// ============================================================================
// Decode output messages
// ============================================================================

decode_output :: proc(data: []u8, out: ^Output_Msg) -> (int, bool) {
    if len(data) < 2 {
        return 0, false
    }
    if data[0] != MAGIC {
        return 0, false
    }
    
    typ := data[1]
    pos := 2
    
    switch typ {
    case MSG_ACK, MSG_CANCEL_ACK:
        if len(data) < ACK_WIRE_SIZE {
            return 0, false
        }
        out.typ = .Ack if typ == MSG_ACK else .Cancel_Ack
        mem.copy(&out.symbol[0], &data[pos], MAX_SYMBOL_LENGTH)
        pos += MAX_SYMBOL_LENGTH
        out.user_id = read_u32_be(data[pos:])
        pos += 4
        out.user_order_id = read_u32_be(data[pos:])
        pos += 4
        return pos, true
        
    case MSG_TRADE:
        if len(data) < TRADE_WIRE_SIZE {
            return 0, false
        }
        out.typ = .Trade
        mem.copy(&out.symbol[0], &data[pos], MAX_SYMBOL_LENGTH)
        pos += MAX_SYMBOL_LENGTH
        out.buy_user_id = read_u32_be(data[pos:])
        pos += 4
        out.buy_order_id = read_u32_be(data[pos:])
        pos += 4
        out.sell_user_id = read_u32_be(data[pos:])
        pos += 4
        out.sell_order_id = read_u32_be(data[pos:])
        pos += 4
        out.price = read_u32_be(data[pos:])
        pos += 4
        out.quantity = read_u32_be(data[pos:])
        pos += 4
        return pos, true
        
    case MSG_TOP_OF_BOOK:
        if len(data) < TOP_OF_BOOK_WIRE_SIZE {
            return 0, false
        }
        out.typ = .Top_Of_Book
        mem.copy(&out.symbol[0], &data[pos], MAX_SYMBOL_LENGTH)
        pos += MAX_SYMBOL_LENGTH
        out.side = Side(data[pos])
        pos += 1
        out.price = read_u32_be(data[pos:])
        pos += 4
        out.quantity = read_u32_be(data[pos:])
        pos += 4
        pos += 1  // pad byte
        return pos, true
        
    case MSG_REJECT:
        if len(data) < REJECT_WIRE_SIZE {
            return 0, false
        }
        out.typ = .Reject
        mem.copy(&out.symbol[0], &data[pos], MAX_SYMBOL_LENGTH)
        pos += MAX_SYMBOL_LENGTH
        out.user_id = read_u32_be(data[pos:])
        pos += 4
        out.user_order_id = read_u32_be(data[pos:])
        pos += 4
        out.reason = Reject_Reason(data[pos])
        pos += 1
        return pos, true
        
    case:
        return 0, false
    }
}
