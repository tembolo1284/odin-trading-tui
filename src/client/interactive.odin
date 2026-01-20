package client

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:bufio"

Interactive_Options :: struct {
    show_prompt:     bool,
    echo_commands:   bool,
    auto_recv:       bool,
    recv_timeout_ms: int,
    danger_burst:    bool,
}

interactive_options_init :: proc(opts: ^Interactive_Options) {
    opts^ = {}
    opts.show_prompt = true
    opts.auto_recv = true
    opts.recv_timeout_ms = 200
}

interactive_response_callback :: proc(msg: ^Output_Msg, user_data: rawptr) {
    switch msg.type {
    case .Ack:
        ack := msg.data.(Ack_Msg)
        fmt.printf("  [ACK] %s user=%d order=%d\n",
            symbol_to_string(ack.symbol[:]), ack.user_id, ack.user_order_id)
    case .Cancel_Ack:
        cack := msg.data.(Cancel_Ack_Msg)
        fmt.printf("  [CANCEL] %s user=%d order=%d\n",
            symbol_to_string(cack.symbol[:]), cack.user_id, cack.user_order_id)
    case .Trade:
        trade := msg.data.(Trade_Msg)
        fmt.printf("  [TRADE] %s buy=%d:%d sell=%d:%d price=%d qty=%d\n",
            symbol_to_string(trade.symbol[:]),
            trade.user_id_buy, trade.user_order_id_buy,
            trade.user_id_sell, trade.user_order_id_sell,
            trade.price, trade.quantity)
    case .Top_Of_Book:
        tob := msg.data.(Top_Of_Book_Msg)
        if tob.price == 0 && tob.total_quantity == 0 {
            fmt.printf("  [TOB] %s %s EMPTY\n",
                symbol_to_string(tob.symbol[:]), tob.side == .Buy ? "BID" : "ASK")
        } else {
            fmt.printf("  [TOB] %s %s price=%d qty=%d\n",
                symbol_to_string(tob.symbol[:]), tob.side == .Buy ? "BID" : "ASK",
                tob.price, tob.total_quantity)
        }
    }
}

Command_Handler :: #type proc(^Engine_Client, []string, ^Interactive_Options) -> bool

Command :: struct {
    name, alias: string,
    handler:     Command_Handler,
    description: string,
}

COMMANDS := []Command{
    {"buy",       "b",    cmd_buy,       "buy SYMBOL QTY@PRICE [order_id]"},
    {"sell",      "s",    cmd_sell,      "sell SYMBOL QTY@PRICE [order_id]"},
    {"cancel",    "c",    cmd_cancel,    "cancel ORDER_ID"},
    {"flush",     "f",    cmd_flush,     "Flush all orders"},
    {"recv",      "r",    cmd_recv,      "recv [timeout_ms]"},
    {"poll",      "p",    cmd_poll,      "Poll messages"},
    {"scenario",  "sc",   cmd_scenario,  "scenario ID"},
    {"scenarios", "list", cmd_scenarios, "List scenarios"},
    {"stats",     "",     cmd_stats,     "Print statistics"},
    {"reset",     "",     cmd_reset,     "Reset stats"},
    {"status",    "",     cmd_status,    "Connection status"},
    {"help",      "h",    cmd_help,      "Show help"},
    {"quit",      "q",    cmd_quit,      "Exit"},
}

cmd_buy :: proc(client: ^Engine_Client, args: []string, opts: ^Interactive_Options) -> bool {
    if len(args) < 3 { fmt.println("Usage: buy SYMBOL QTY@PRICE"); return true }
    symbol := args[1]
    parts := strings.split(args[2], "@")
    defer delete(parts)
    if len(parts) != 2 { fmt.println("Use QTY@PRICE format"); return true }
    qty, ok1 := strconv.parse_uint(parts[0], 10)
    price, ok2 := strconv.parse_uint(parts[1], 10)
    if !ok1 || !ok2 { fmt.println("Invalid number"); return true }
    order_id: u32 = 0
    if len(args) > 3 { if oid, ok := strconv.parse_uint(args[3], 10); ok { order_id = u32(oid) } }
    oid := engine_client_send_order(client, symbol, u32(price), u32(qty), .Buy, order_id)
    if oid > 0 {
        fmt.printf("Sent BUY %s %d@%d (order_id=%d)\n", symbol, qty, price, oid)
        if opts.auto_recv { engine_client_recv_all(client, opts.recv_timeout_ms) }
    } else { fmt.println("Failed") }
    return true
}

cmd_sell :: proc(client: ^Engine_Client, args: []string, opts: ^Interactive_Options) -> bool {
    if len(args) < 3 { fmt.println("Usage: sell SYMBOL QTY@PRICE"); return true }
    symbol := args[1]
    parts := strings.split(args[2], "@")
    defer delete(parts)
    if len(parts) != 2 { fmt.println("Use QTY@PRICE format"); return true }
    qty, ok1 := strconv.parse_uint(parts[0], 10)
    price, ok2 := strconv.parse_uint(parts[1], 10)
    if !ok1 || !ok2 { fmt.println("Invalid number"); return true }
    order_id: u32 = 0
    if len(args) > 3 { if oid, ok := strconv.parse_uint(args[3], 10); ok { order_id = u32(oid) } }
    oid := engine_client_send_order(client, symbol, u32(price), u32(qty), .Sell, order_id)
    if oid > 0 {
        fmt.printf("Sent SELL %s %d@%d (order_id=%d)\n", symbol, qty, price, oid)
        if opts.auto_recv { engine_client_recv_all(client, opts.recv_timeout_ms) }
    } else { fmt.println("Failed") }
    return true
}

cmd_cancel :: proc(client: ^Engine_Client, args: []string, opts: ^Interactive_Options) -> bool {
    if len(args) < 2 { fmt.println("Usage: cancel ORDER_ID"); return true }
    order_id, ok := strconv.parse_uint(args[1], 10)
    if !ok { fmt.println("Invalid order ID"); return true }
    if engine_client_send_cancel(client, u32(order_id)) {
        fmt.printf("Sent CANCEL order_id=%d\n", order_id)
        if opts.auto_recv { engine_client_recv_all(client, opts.recv_timeout_ms) }
    } else { fmt.println("Failed") }
    return true
}

cmd_flush :: proc(client: ^Engine_Client, args: []string, opts: ^Interactive_Options) -> bool {
    if engine_client_send_flush(client) {
        fmt.println("Sent FLUSH")
        if opts.auto_recv { engine_client_recv_all(client, opts.recv_timeout_ms) }
    } else { fmt.println("Failed") }
    return true
}

cmd_recv :: proc(client: ^Engine_Client, args: []string, opts: ^Interactive_Options) -> bool {
    timeout := 500
    if len(args) > 1 { if t, ok := strconv.parse_int(args[1], 10); ok { timeout = int(t) } }
    count := engine_client_recv_all(client, timeout)
    fmt.printf("Received %d messages\n", count)
    return true
}

cmd_poll :: proc(client: ^Engine_Client, args: []string, opts: ^Interactive_Options) -> bool {
    count := engine_client_poll(client)
    fmt.printf("Polled %d messages\n", count)
    return true
}

cmd_scenario :: proc(client: ^Engine_Client, args: []string, opts: ^Interactive_Options) -> bool {
    if len(args) < 2 { scenario_print_list(); return true }
    id, ok := strconv.parse_int(args[1], 10)
    if !ok { fmt.println("Invalid scenario ID"); return true }
    result: Scenario_Result
    scenario_run(client, int(id), opts.danger_burst, &result)
    return true
}

cmd_scenarios :: proc(client: ^Engine_Client, args: []string, opts: ^Interactive_Options) -> bool {
    scenario_print_list()
    return true
}

cmd_stats :: proc(client: ^Engine_Client, args: []string, opts: ^Interactive_Options) -> bool {
    engine_client_print_stats(client)
    return true
}

cmd_reset :: proc(client: ^Engine_Client, args: []string, opts: ^Interactive_Options) -> bool {
    engine_client_reset_stats(client)
    engine_client_reset_order_id(client, 1)
    fmt.println("Reset complete")
    return true
}

cmd_status :: proc(client: ^Engine_Client, args: []string, opts: ^Interactive_Options) -> bool {
    fmt.printf("Connected: %s, Transport: %s, Encoding: %s, NextID: %d\n",
        engine_client_is_connected(client) ? "yes" : "no",
        transport_type_str(engine_client_get_transport(client)),
        encoding_type_str(engine_client_get_encoding(client)),
        engine_client_peek_next_order_id(client))
    return true
}

cmd_help :: proc(client: ^Engine_Client, args: []string, opts: ^Interactive_Options) -> bool {
    interactive_print_help()
    return true
}

cmd_quit :: proc(client: ^Engine_Client, args: []string, opts: ^Interactive_Options) -> bool {
    fmt.println("Goodbye!")
    return false
}

find_command :: proc(name: string) -> ^Command {
    for &cmd in COMMANDS {
        if strings.equal_fold(name, cmd.name) || (cmd.alias != "" && strings.equal_fold(name, cmd.alias)) {
            return &cmd
        }
    }
    return nil
}

interactive_print_help :: proc() {
    fmt.println("\nCommands:")
    for cmd in COMMANDS {
        if cmd.alias != "" {
            fmt.printf("  %-10s (%-2s)  %s\n", cmd.name, cmd.alias, cmd.description)
        } else {
            fmt.printf("  %-10s       %s\n", cmd.name, cmd.description)
        }
    }
    fmt.println()
}

interactive_execute :: proc(client: ^Engine_Client, line: string, opts: ^Interactive_Options) -> bool {
    trimmed := strings.trim_space(line)
    if len(trimmed) == 0 || trimmed[0] == '#' { return true }
    
    parts := strings.split(trimmed, " ")
    defer delete(parts)
    if len(parts) == 0 { return true }
    
    cmd := find_command(parts[0])
    if cmd == nil {
        fmt.printf("Unknown command: %s (type 'help')\n", parts[0])
        return true
    }
    return cmd.handler(client, parts, opts)
}

interactive_run :: proc(client: ^Engine_Client, opts: ^Interactive_Options) -> int {
    engine_client_set_response_callback(client, interactive_response_callback, nil)
    
    fmt.println("\nMatching Engine Client - Interactive Mode")
    fmt.println("Type 'help' for commands, 'quit' to exit\n")
    
    buf: [1024]u8
    for {
        if opts.show_prompt {
            fmt.print("> ")
        }
        
        n, err := os.read(os.stdin, buf[:])
        if err != os.ERROR_NONE || n <= 0 {
            fmt.println()
            break
        }
        
        line := string(buf[:n])
        if !interactive_execute(client, line, opts) {
            break
        }
        
        if client.multicast_active {
            engine_client_poll(client)
        }
    }
    
    return 0
}
