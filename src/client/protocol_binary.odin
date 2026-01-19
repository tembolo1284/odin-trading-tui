// src/client/protocol_binary.odin
package client

import "core:mem"

MAGIC :: u8(0x4D) // 'M'

MSG_NEW_ORDER   :: u8('N')
MSG_CANCEL      :: u8('C')
MSG_FLUSH       :: u8('F')

MSG_ACK         :: u8('A')
MSG_CANCEL_ACK  :: u8('X')
MSG_TRADE       :: u8('T')
MSG_TOP_OF_BOOK :: u8('B')
MSG_REJECT      :: u8('R')

MAX_SYMBOL_LENGTH :: 8

NEW_ORDER_WIRE_SIZE   :: 27
CANCEL_WIRE_SIZE      :: 10
FLUSH_WIRE_SIZE       :: 2
ACK_WIRE_SIZE         :: 18
CANCEL_ACK_WIRE_SIZE  :: 18
TRADE_WIRE_SIZE       :: 34
TOP_OF_BOOK_WIRE_SIZE :: 20
REJECT_WIRE_SIZE      :: 19

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

Output_Msg :: struct {
    typ: Output_Type,
    symbol: [MAX_SYMBOL_LENGTH]u8,

    // ack/cancel_ack/reject basics
    user_id: u32,
    user_order_id: u32,

    // trade
    buy_user_id:  u32,
    buy_order_id: u32,
    sell_user_id: u32,
    sell_order_id:u32,
    price:        u32,
    quantity:     u32,

    // top-of-book
    side: Side,

    // reject
    reason: Reject_Reason,
}

// ===== Big-endian helpers =====
write_u32_be :: proc(buf: []u8, v: u32) {
    buf[0] = u8(v >> 24)
    buf[1] = u8(v >> 16)
    buf[2] = u8(v >> 8)
    buf[3] = u8(v)
}

read_u32_be :: proc(buf: []u8) -> u32 {
    return (u32(buf[0]) << 24) | (u32(buf[1]) << 16) | (u32(buf[2]) << 8) | u32(buf[3])
}

write_symbol_8 :: proc(dst: []u8, sym: string) {
    n := min(len(dst), len(sym))
    for i in 0..<n { dst[i] = sym[i] }
    for i in n..<len(dst) { dst[i] = 0 }
}

symbol_to_string :: proc(sym: []u8) -> string {
    for i in 0..<len(sym) {
        if sym[i] == 0 { return string(sym[:i]) }
    }
    return string(sym[:])
}

// ===== Encode input payload (NOT including 4-byte TCP frame length) =====
encode_new_order_binary :: proc(
    buf: []u8,
    user_id: u32,
    symbol: string,
    price: u32,
    qty: u32,
    side: Side,
    user_order_id: u32,
) -> (n: int, ok: bool) {
    if len(buf) < NEW_ORDER_WIRE_SIZE { return 0, false }
    if qty == 0 { return 0, false }
    if len(symbol) == 0 { return 0, false }

    pos := 0
    buf[pos] = MAGIC;         pos += 1
    buf[pos] = MSG_NEW_ORDER; pos += 1

    write_u32_be(buf[pos:pos+4], user_id); pos += 4
    write_symbol_8(buf[pos:pos+8], symbol); pos += 8
    write_u32_be(buf[pos:pos+4], price); pos += 4
    write_u32_be(buf[pos:pos+4], qty); pos += 4

    buf[pos] = u8(side); pos += 1
    write_u32_be(buf[pos:pos+4], user_order_id); pos += 4

    return pos, pos == NEW_ORDER_WIRE_SIZE
}

encode_cancel_binary :: proc(buf: []u8, user_id: u32, user_order_id: u32) -> (n: int, ok: bool) {
    if len(buf) < CANCEL_WIRE_SIZE { return 0, false }
    if user_id == 0 && user_order_id == 0 { return 0, false }

    pos := 0
    buf[pos] = MAGIC;        pos += 1
    buf[pos] = MSG_CANCEL;   pos += 1
    write_u32_be(buf[pos:pos+4], user_id);       pos += 4
    write_u32_be(buf[pos:pos+4], user_order_id); pos += 4

    return pos, pos == CANCEL_WIRE_SIZE
}

encode_flush_binary :: proc(buf: []u8) -> (n: int, ok: bool) {
    if len(buf) < FLUSH_WIRE_SIZE { return 0, false }
    buf[0] = MAGIC
    buf[1] = MSG_FLUSH
    return FLUSH_WIRE_SIZE, true
}

// ===== Decode output payload (NOT including 4-byte TCP frame length) =====
decode_output_binary :: proc(data: []u8, out: ^Output_Msg) -> (consumed: int, ok: bool) {
    if len(data) < 2 { return 0, false }
    if data[0] != MAGIC { return 0, false }

    typ := data[1]
    pos := 2

    read_sym8 :: proc(dst: []u8, src: []u8) {
        mem.copy(dst, src[:8])
    }

    switch typ {
    case MSG_ACK, MSG_CANCEL_ACK:
        if len(data) < ACK_WIRE_SIZE { return 0, false }
        out.typ = Output_Type(typ)
        read_sym8(out.symbol[:], data[pos:]); pos += 8
        out.user_id = read_u32_be(data[pos:pos+4]); pos += 4
        out.user_order_id = read_u32_be(data[pos:pos+4]); pos += 4
        return pos, true

    case MSG_TRADE:
        if len(data) < TRADE_WIRE_SIZE { return 0, false }
        out.typ = .Trade
        read_sym8(out.symbol[:], data[pos:]); pos += 8
        out.buy_user_id   = read_u32_be(data[pos:pos+4]); pos += 4
        out.buy_order_id  = read_u32_be(data[pos:pos+4]); pos += 4
        out.sell_user_id  = read_u32_be(data[pos:pos+4]); pos += 4
        out.sell_order_id = read_u32_be(data[pos:pos+4]); pos += 4
        out.price         = read_u32_be(data[pos:pos+4]); pos += 4
        out.quantity      = read_u32_be(data[pos:pos+4]); pos += 4
        return pos, true

    case MSG_TOP_OF_BOOK:
        if len(data) < TOP_OF_BOOK_WIRE_SIZE { return 0, false }
        out.typ = .Top_Of_Book
        read_sym8(out.symbol[:], data[pos:]); pos += 8
        out.side = Side(data[pos]); pos += 1
        out.price = read_u32_be(data[pos:pos+4]); pos += 4
        out.quantity = read_u32_be(data[pos:pos+4]); pos += 4
        pos += 1 // pad byte
        return pos, true

    case MSG_REJECT:
        if len(data) < REJECT_WIRE_SIZE { return 0, false }
        out.typ = .Reject
        read_sym8(out.symbol[:], data[pos:]); pos += 8
        out.user_id = read_u32_be(data[pos:pos+4]); pos += 4
        out.user_order_id = read_u32_be(data[pos:pos+4]); pos += 4
        out.reason = Reject_Reason(data[pos]); pos += 1
        return pos, true

    default:
        return 0, false
    }
}

