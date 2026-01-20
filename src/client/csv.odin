package client

// =============================================================================
// CSV Protocol
//
// Human-readable message format for debugging and testing.
// =============================================================================

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

// =============================================================================
// Encoding Functions
// =============================================================================

// Encode a new order to CSV format
// Returns number of bytes written
csv_encode_new_order :: proc(
    buffer: []u8,
    user_id: u32,
    symbol: string,
    price: u32,
    quantity: u32,
    side: Side,
    order_id: u32,
) -> int {
    s := fmt.bprintf(buffer, "N, %d, %s, %d, %d, %c, %d\n",
        user_id, symbol, price, quantity, side_to_char(side), order_id)
    return len(s)
}

// Encode a cancel to CSV format
csv_encode_cancel :: proc(buffer: []u8, user_id: u32, order_id: u32) -> int {
    s := fmt.bprintf(buffer, "C, %d, %d\n", user_id, order_id)
    return len(s)
}

// Encode a flush to CSV format
csv_encode_flush :: proc(buffer: []u8) -> int {
    if len(buffer) < 2 {
        return 0
    }
    buffer[0] = 'F'
    buffer[1] = '\n'
    return 2
}

// =============================================================================
// Decoding Functions
// =============================================================================

// Helper to trim whitespace from beginning of string
trim_left :: proc(s: string) -> string {
    i := 0
    for i < len(s) && (s[i] == ' ' || s[i] == '\t') {
        i += 1
    }
    return s[i:]
}

// Helper to trim newlines from end of string
trim_right :: proc(s: string) -> string {
    i := len(s)
    for i > 0 && (s[i-1] == '\n' || s[i-1] == '\r') {
        i -= 1
    }
    return s[:i]
}

// Parse a CSV response message
// Format: A, symbol, userId, orderId
//         C, symbol, userId, orderId
//         T, symbol, buyUser, buyOrd, sellUser, sellOrd, price, qty
//         B, symbol, side, price, qty  (or B, symbol, side, -, -)
csv_decode_response :: proc(data: []u8, msg: ^Output_Msg) -> bool {
    line := string(data)
    line = trim_right(line)

    if len(line) == 0 {
        return false
    }

    // Split by comma
    parts := strings.split(line, ",")
    defer delete(parts)

    if len(parts) < 1 {
        return false
    }

    msg_type := trim_left(parts[0])
    if len(msg_type) == 0 {
        return false
    }

    switch msg_type[0] {
    case 'A':
        // A, symbol, userId, orderId
        if len(parts) < 4 do return false

        msg.type = .Ack
        ack: Ack_Msg

        sym := trim_left(parts[1])
        copy_symbol(ack.symbol[:], sym)

        uid, ok1 := strconv.parse_uint(trim_left(parts[2]), 10)
        if !ok1 do return false
        ack.user_id = u32(uid)

        oid, ok2 := strconv.parse_uint(trim_left(parts[3]), 10)
        if !ok2 do return false
        ack.user_order_id = u32(oid)

        msg.data = ack
        return true

    case 'C':
        // C, symbol, userId, orderId (Cancel Ack)
        if len(parts) < 4 do return false

        msg.type = .Cancel_Ack
        cack: Cancel_Ack_Msg

        sym := trim_left(parts[1])
        copy_symbol(cack.symbol[:], sym)

        uid, ok1 := strconv.parse_uint(trim_left(parts[2]), 10)
        if !ok1 do return false
        cack.user_id = u32(uid)

        oid, ok2 := strconv.parse_uint(trim_left(parts[3]), 10)
        if !ok2 do return false
        cack.user_order_id = u32(oid)

        msg.data = cack
        return true

    case 'T':
        // T, symbol, buyUser, buyOrd, sellUser, sellOrd, price, qty
        if len(parts) < 8 do return false

        msg.type = .Trade
        trade: Trade_Msg

        sym := trim_left(parts[1])
        copy_symbol(trade.symbol[:], sym)

        v, ok: uint
        v, ok = strconv.parse_uint(trim_left(parts[2]), 10)
        if !ok do return false
        trade.user_id_buy = u32(v)

        v, ok = strconv.parse_uint(trim_left(parts[3]), 10)
        if !ok do return false
        trade.user_order_id_buy = u32(v)

        v, ok = strconv.parse_uint(trim_left(parts[4]), 10)
        if !ok do return false
        trade.user_id_sell = u32(v)

        v, ok = strconv.parse_uint(trim_left(parts[5]), 10)
        if !ok do return false
        trade.user_order_id_sell = u32(v)

        v, ok = strconv.parse_uint(trim_left(parts[6]), 10)
        if !ok do return false
        trade.price = u32(v)

        v, ok = strconv.parse_uint(trim_left(parts[7]), 10)
        if !ok do return false
        trade.quantity = u32(v)

        msg.data = trade
        return true

    case 'B':
        // B, symbol, side, price, qty  (or B, symbol, side, -, -)
        if len(parts) < 5 do return false

        msg.type = .Top_Of_Book
        tob: Top_Of_Book_Msg

        sym := trim_left(parts[1])
        copy_symbol(tob.symbol[:], sym)

        side_str := trim_left(parts[2])
        if len(side_str) > 0 {
            tob.side, _ = side_from_char(side_str[0])
        }

        price_str := trim_left(parts[3])
        if price_str == "-" {
            tob.price = 0
        } else {
            v, ok := strconv.parse_uint(price_str, 10)
            if !ok do return false
            tob.price = u32(v)
        }

        qty_str := trim_left(parts[4])
        if qty_str == "-" {
            tob.total_quantity = 0
        } else {
            v, ok := strconv.parse_uint(qty_str, 10)
            if !ok do return false
            tob.total_quantity = u32(v)
        }

        msg.data = tob
        return true

    case:
        return false
    }
}
