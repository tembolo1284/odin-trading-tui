package client

import "core:fmt"
import "core:time"
import "core:os"

// ============================================================================
// Test scenarios for the matching engine
// ============================================================================

Scenario :: enum {
    // Basic scenarios (1-9)
    Buy_Sell_No_Match     = 1,   // Buy and sell at different prices, flush
    Buy_Sell_Full_Match   = 2,   // Buy and sell that fully match
    Buy_Then_Cancel       = 3,   // Place order then cancel it
    
    // Stress tests - single symbol (20-29)
    Stress_2k_Orders      = 20,  // 2,000 orders -> 1,000 trades
    Stress_20k_Orders     = 21,  // 20,000 orders -> 10,000 trades
    Stress_200k_Orders    = 22,  // 200,000 orders -> 100,000 trades
    
    // Stress tests - dual symbol/processor (30-39)
    Dual_2k_Orders        = 30,  // 2,000 orders split AAPL/TSLA
    Dual_20k_Orders       = 31,  // 20,000 orders split AAPL/TSLA
}

// ============================================================================
// Scenario runner
// ============================================================================

run_scenario :: proc(fd: os.Handle, scenario: Scenario, verbose: bool = true) -> (Scenario_Stats, bool) {
    stats := Scenario_Stats{}
    stats.start_time = time.now()._nsec
    
    ok: bool
    switch scenario {
    case .Buy_Sell_No_Match:
        ok = scenario_buy_sell_no_match(fd, &stats, verbose)
    case .Buy_Sell_Full_Match:
        ok = scenario_buy_sell_full_match(fd, &stats, verbose)
    case .Buy_Then_Cancel:
        ok = scenario_buy_then_cancel(fd, &stats, verbose)
    case .Stress_2k_Orders:
        ok = scenario_stress_single(fd, &stats, 2000, verbose)
    case .Stress_20k_Orders:
        ok = scenario_stress_single(fd, &stats, 20000, verbose)
    case .Stress_200k_Orders:
        ok = scenario_stress_single(fd, &stats, 200000, verbose)
    case .Dual_2k_Orders:
        ok = scenario_stress_dual(fd, &stats, 2000, verbose)
    case .Dual_20k_Orders:
        ok = scenario_stress_dual(fd, &stats, 20000, verbose)
    case:
        fmt.println("Unknown scenario:", scenario)
        return stats, false
    }
    
    stats.end_time = time.now()._nsec
    return stats, ok
}

print_stats :: proc(stats: ^Scenario_Stats) {
    elapsed_ns := stats.end_time - stats.start_time
    elapsed_ms := f64(elapsed_ns) / 1_000_000.0
    elapsed_s := elapsed_ms / 1000.0
    
    total_msgs := stats.orders_sent + stats.cancels_sent
    throughput := f64(total_msgs) / elapsed_s if elapsed_s > 0 else 0
    
    fmt.println("──────────────────────────────────")
    fmt.println("Results:")
    fmt.printf("  Orders sent:     %d\n", stats.orders_sent)
    fmt.printf("  Cancels sent:    %d\n", stats.cancels_sent)
    fmt.printf("  ACKs received:   %d\n", stats.acks_received)
    fmt.printf("  Trades received: %d\n", stats.trades_received)
    fmt.printf("  Cancel ACKs:     %d\n", stats.cancel_acks)
    fmt.printf("  Top of Book:     %d\n", stats.tob_received)
    fmt.printf("  Rejects:         %d\n", stats.rejects)
    fmt.println("──────────────────────────────────")
    fmt.printf("  Elapsed:         %.2f ms\n", elapsed_ms)
    fmt.printf("  Throughput:      %.0f msgs/sec\n", throughput)
    fmt.println("──────────────────────────────────")
}

// ============================================================================
// Response handling - receive and process one message
// ============================================================================

recv_one :: proc(fd: os.Handle, stats: ^Scenario_Stats, verbose: bool) -> (Output_Msg, bool) {
    recv_buf: [4096]u8
    
    payload_len, ok := recv_frame(fd, recv_buf[:])
    if !ok {
        return {}, false
    }
    
    out: Output_Msg
    _, decode_ok := decode_output(recv_buf[:payload_len], &out)
    if !decode_ok {
        if verbose {
            fmt.println("  !! Failed to decode response (len=", payload_len, ")")
        }
        return {}, false
    }
    
    sym := symbol_to_string(out.symbol[:])
    
    switch out.typ {
    case .Ack:
        stats.acks_received += 1
        if verbose {
            fmt.printf("[RECV] A, %s, %d, %d\n", sym, out.user_id, out.user_order_id)
        }
    case .Cancel_Ack:
        stats.cancel_acks += 1
        if verbose {
            fmt.printf("[RECV] C, %s, %d, %d\n", sym, out.user_id, out.user_order_id)
        }
    case .Trade:
        stats.trades_received += 1
        if verbose {
            fmt.printf("[RECV] T, %s, buy=%d/%d, sell=%d/%d, px=%d, qty=%d\n", 
                sym, out.buy_user_id, out.buy_order_id, 
                out.sell_user_id, out.sell_order_id,
                out.price, out.quantity)
        }
    case .Top_Of_Book:
        stats.tob_received += 1
        if verbose {
            side_char := 'B' if out.side == .Buy else 'S'
            if out.quantity == 0 {
                fmt.printf("[RECV] B, %s, %c, -, -\n", sym, side_char)
            } else {
                fmt.printf("[RECV] B, %s, %c, %d, %d\n", sym, side_char, out.price, out.quantity)
            }
        }
    case .Reject:
        stats.rejects += 1
        if verbose {
            fmt.printf("[RECV] R, %s, %d, %d, reason=%d\n", 
                sym, out.user_id, out.user_order_id, u8(out.reason))
        }
    }
    
    return out, true
}

// Receive exactly N messages
recv_n :: proc(fd: os.Handle, stats: ^Scenario_Stats, count: int, verbose: bool) -> bool {
    for _ in 0..<count {
        _, ok := recv_one(fd, stats, verbose)
        if !ok {
            return false
        }
    }
    return true
}

// ============================================================================
// Scenario implementations
// ============================================================================

// Scenario 1: Buy and sell at different prices (no match), then flush
scenario_buy_sell_no_match :: proc(fd: os.Handle, stats: ^Scenario_Stats, verbose: bool) -> bool {
    if verbose {
        fmt.println("=== Scenario 1: Simple Orders (no match) ===")
    }
    
    buf: [64]u8
    
    // Send BUY @ 100
    if verbose { fmt.println("Sending: BUY IBM 50@100") }
    n, ok := encode_new_order(buf[:], 1, "IBM", 10000, 50, .Buy, 1)
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    stats.orders_sent += 1
    
    // Wait for ACK
    if !recv_n(fd, stats, 1, verbose) {
        return false
    }
    
    // Send SELL @ 105 (no match)
    if verbose { fmt.println("Sending: SELL IBM 50@105") }
    n, ok = encode_new_order(buf[:], 1, "IBM", 10500, 50, .Sell, 2)
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    stats.orders_sent += 1
    
    // Wait for ACK
    if !recv_n(fd, stats, 1, verbose) {
        return false
    }
    
    // Flush (cancels all orders)
    if verbose { fmt.println("Sending: FLUSH") }
    n, ok = encode_flush(buf[:])
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    
    // Expect: 2 Cancel ACKs + 2 Top of Book (empty for buy/sell side)
    if !recv_n(fd, stats, 4, verbose) {
        return false
    }
    
    return true
}

// Scenario 2: Buy and sell that fully match
scenario_buy_sell_full_match :: proc(fd: os.Handle, stats: ^Scenario_Stats, verbose: bool) -> bool {
    if verbose {
        fmt.println("=== Scenario 2: Matching Orders ===")
    }
    
    buf: [64]u8
    
    // Send BUY @ 100
    if verbose { fmt.println("Sending: BUY IBM 50@100") }
    n, ok := encode_new_order(buf[:], 1, "IBM", 10000, 50, .Buy, 1)
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    stats.orders_sent += 1
    
    // Wait for ACK
    if !recv_n(fd, stats, 1, verbose) {
        return false
    }
    
    // Send SELL @ 100 (matches!)
    if verbose { fmt.println("Sending: SELL IBM 50@100") }
    n, ok = encode_new_order(buf[:], 2, "IBM", 10000, 50, .Sell, 1)
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    stats.orders_sent += 1
    
    // Expect: ACK for sell + Trade
    // (Some engines send 2 trades, one per side - adjust if needed)
    if !recv_n(fd, stats, 2, verbose) {
        return false
    }
    
    return true
}

// Scenario 3: Place order then cancel it
scenario_buy_then_cancel :: proc(fd: os.Handle, stats: ^Scenario_Stats, verbose: bool) -> bool {
    if verbose {
        fmt.println("=== Scenario 3: Order + Cancel ===")
    }
    
    buf: [64]u8
    
    // Send BUY
    if verbose { fmt.println("Sending: BUY IBM 50@100") }
    n, ok := encode_new_order(buf[:], 1, "IBM", 10000, 50, .Buy, 1)
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    stats.orders_sent += 1
    
    // Wait for ACK
    if !recv_n(fd, stats, 1, verbose) {
        return false
    }
    
    // Cancel
    if verbose { fmt.println("Sending: CANCEL user=1 order=1") }
    n, ok = encode_cancel(buf[:], 1, 1)
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    stats.cancels_sent += 1
    
    // Wait for Cancel ACK
    if !recv_n(fd, stats, 1, verbose) {
        return false
    }
    
    return true
}

// Scenario 20-22: Stress test single symbol
scenario_stress_single :: proc(fd: os.Handle, stats: ^Scenario_Stats, order_count: int, verbose: bool) -> bool {
    fmt.printf("=== Stress Test: %d orders (single symbol) ===\n", order_count)
    fmt.println("Expecting", order_count/2, "trades")
    
    buf: [64]u8
    half := order_count / 2
    price := u32(10000)  // $100.00
    
    // Send all BUYs first
    fmt.println("Sending", half, "BUY orders...")
    for i in 0..<half {
        n, ok := encode_new_order(buf[:], 1, "AAPL", price, 100, .Buy, u32(i + 1))
        if !ok || !send_frame(fd, buf[:n]) {
            fmt.println("Failed at BUY order", i)
            return false
        }
        stats.orders_sent += 1
        
        // Receive ACK immediately to avoid buffer buildup
        if !recv_n(fd, stats, 1, false) {
            fmt.println("Failed to receive ACK for BUY", i)
            return false
        }
    }
    
    // Send all SELLs (will match)
    fmt.println("Sending", half, "SELL orders (will match)...")
    for i in 0..<half {
        n, ok := encode_new_order(buf[:], 2, "AAPL", price, 100, .Sell, u32(i + 1))
        if !ok || !send_frame(fd, buf[:n]) {
            fmt.println("Failed at SELL order", i)
            return false
        }
        stats.orders_sent += 1
        
        // Receive ACK + Trade
        if !recv_n(fd, stats, 2, false) {
            fmt.println("Failed to receive responses for SELL", i)
            return false
        }
    }
    
    fmt.println("Done!")
    return true
}

// Scenario 30-31: Stress test dual symbols (for dual-processor routing)
scenario_stress_dual :: proc(fd: os.Handle, stats: ^Scenario_Stats, order_count: int, verbose: bool) -> bool {
    fmt.printf("=== Stress Test: %d orders (dual symbol AAPL/TSLA) ===\n", order_count)
    fmt.println("Expecting", order_count/2, "trades total")
    
    buf: [64]u8
    quarter := order_count / 4
    price := u32(10000)
    
    symbols := [2]string{"AAPL", "TSLA"}
    
    // Send BUYs for both symbols
    fmt.println("Sending", quarter * 2, "BUY orders across AAPL/TSLA...")
    for i in 0..<quarter {
        for sym_idx in 0..<2 {
            n, ok := encode_new_order(
                buf[:], 
                u32(sym_idx + 1),
                symbols[sym_idx], 
                price, 
                100, 
                .Buy, 
                u32(i + 1),
            )
            if !ok || !send_frame(fd, buf[:n]) {
                return false
            }
            stats.orders_sent += 1
            
            if !recv_n(fd, stats, 1, false) {
                return false
            }
        }
    }
    
    // Send SELLs for both symbols (will match)
    fmt.println("Sending", quarter * 2, "SELL orders across AAPL/TSLA...")
    for i in 0..<quarter {
        for sym_idx in 0..<2 {
            n, ok := encode_new_order(
                buf[:], 
                u32(sym_idx + 10),
                symbols[sym_idx], 
                price, 
                100, 
                .Sell, 
                u32(i + 1),
            )
            if !ok || !send_frame(fd, buf[:n]) {
                return false
            }
            stats.orders_sent += 1
            
            // ACK + Trade
            if !recv_n(fd, stats, 2, false) {
                return false
            }
        }
    }
    
    fmt.println("Done!")
    return true
}
