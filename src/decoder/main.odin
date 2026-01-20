package decoder

import "core:fmt"
import "core:os"

BINARY_MAGIC :: 0x4D
BINARY_SYMBOL_LEN :: 8

Binary_Ack :: struct #packed {
    magic:         u8,
    msg_type:      u8,
    symbol:        [BINARY_SYMBOL_LEN]u8,
    user_id:       u32be,
    user_order_id: u32be,
}

Binary_Cancel_Ack :: struct #packed {
    magic:         u8,
    msg_type:      u8,
    symbol:        [BINARY_SYMBOL_LEN]u8,
    user_id:       u32be,
    user_order_id: u32be,
}

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

Binary_Top_Of_Book :: struct #packed {
    magic:    u8,
    msg_type: u8,
    symbol:   [BINARY_SYMBOL_LEN]u8,
    side:     u8,
    price:    u32be,
    quantity: u32be,
}

extract_symbol :: proc(sym: []u8) -> string {
    n := 0
    for i in 0..<len(sym) {
        if sym[i] == 0 { break }
        n = i + 1
    }
    return string(sym[:n])
}

decode_message :: proc(data: []u8) {
    if len(data) < 2 || data[0] != BINARY_MAGIC {
        fmt.println("Not a binary message")
        return
    }
    
    msg_type := data[1]
    
    switch msg_type {
    case 'A':
        if len(data) < size_of(Binary_Ack) { fmt.println("Incomplete ACK"); return }
        ack := cast(^Binary_Ack)raw_data(data)
        fmt.printf("A, %s, %d, %d\n",
            extract_symbol(ack.symbol[:]), u32(ack.user_id), u32(ack.user_order_id))
    
    case 'X':
        if len(data) < size_of(Binary_Cancel_Ack) { fmt.println("Incomplete CANCEL_ACK"); return }
        cack := cast(^Binary_Cancel_Ack)raw_data(data)
        fmt.printf("C, %s, %d, %d\n",
            extract_symbol(cack.symbol[:]), u32(cack.user_id), u32(cack.user_order_id))
    
    case 'T':
        if len(data) < size_of(Binary_Trade) { fmt.println("Incomplete TRADE"); return }
        trade := cast(^Binary_Trade)raw_data(data)
        fmt.printf("T, %s, %d, %d, %d, %d, %d, %d\n",
            extract_symbol(trade.symbol[:]),
            u32(trade.user_id_buy), u32(trade.user_order_id_buy),
            u32(trade.user_id_sell), u32(trade.user_order_id_sell),
            u32(trade.price), u32(trade.quantity))
    
    case 'B':
        if len(data) < size_of(Binary_Top_Of_Book) { fmt.println("Incomplete TOB"); return }
        tob := cast(^Binary_Top_Of_Book)raw_data(data)
        price := u32(tob.price)
        qty := u32(tob.quantity)
        if price == 0 {
            fmt.printf("B, %s, %c, -, -\n", extract_symbol(tob.symbol[:]), tob.side)
        } else {
            fmt.printf("B, %s, %c, %d, %d\n", extract_symbol(tob.symbol[:]), tob.side, price, qty)
        }
    
    case:
        fmt.printf("Unknown message type: 0x%02X\n", msg_type)
    }
}

msg_size :: proc(msg_type: u8) -> int {
    switch msg_type {
    case 'A': return size_of(Binary_Ack)
    case 'X': return size_of(Binary_Cancel_Ack)
    case 'T': return size_of(Binary_Trade)
    case 'B': return size_of(Binary_Top_Of_Book)
    case:     return 2
    }
}

main :: proc() {
    fmt.println("Binary Message Decoder")
    fmt.println("Reading from stdin...\n")
    
    buffer: [1024]u8
    
    for {
        n, err := os.read(os.stdin, buffer[:])
        if err != os.ERROR_NONE || n <= 0 { break }
        
        offset := 0
        for offset < n {
            if buffer[offset] == BINARY_MAGIC {
                size := 0
                if offset + 1 < n {
                    size = msg_size(buffer[offset + 1])
                }
                if offset + size <= n {
                    decode_message(buffer[offset:offset+size])
                    offset += size
                } else {
                    break
                }
            } else {
                offset += 1
            }
        }
    }
}
