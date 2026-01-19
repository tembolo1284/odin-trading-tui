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

run_scenario :: proc(fd: os.Handle, scenario: Scenario) -> (Scenario_Stats, bool) {
    stats := Scenario_Stats{}
    stats.start_time = time.now()._nsec
    
    ok: bool
    switch scenario {
    case .Buy_Sell_No_Match:
        ok = scenario_buy_sell_no_match(fd, &stats)
    case .Buy_Sell_Full_Match:
        ok = scenario_buy_sell_full_match(fd, &stats)
    case .Buy_Then_Cancel:
        ok = scenario_buy_then_cancel(fd, &stats)
    case .Stress_2k_Orders:
        ok = scenario_stress_single(fd, &stats, 2000)
    case .Stress_20k_Orders:
        ok = scenario_stress_single(fd, &stats, 20000)
    case .Stress_200k_Orders:
        ok = scenario_stress_single(fd, &stats, 200000)
    case .Dual_2k_Orders:
        ok = scenario_stress_dual(fd, &stats, 2000)
    case .Dual_20k_Orders:
        ok = scenario_stress_dual(fd, &stats, 20000)
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
    fmt.printf("  Rejects:         %d\n", stats.rejects)
    fmt.println("──────────────────────────────────")
    fmt.printf("  Elapsed:         %.2f ms\n", elapsed_ms)
    fmt.printf("  Throughput:      %.0f msgs/sec\n", throughput)
    fmt.println("──────────────────────────────────")
}

// ============================================================================
// Scenario implementations
// ============================================================================

// Scenario 1: Buy and sell at different prices (no match), then flush
scenario_buy_sell_no_match :: proc(fd: os.Handle, stats: ^Scenario_Stats) -> bool {
    fmt.println("Scenario 1: Buy/Sell no match + Flush")
    
    buf: [64]u8
    
    // Send BUY @ 100
    n, ok := encode_new_order(buf[:], 1, "AAPL", 10000, 100, .Buy, 1)
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    stats.orders_sent += 1
    fmt.println("  -> Sent BUY  AAPL 100@100.00")
    
    // Send SELL @ 110 (no match)
    n, ok = encode_new_order(buf[:], 1, "AAPL", 11000, 100, .Sell, 2)
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    stats.orders_sent += 1
    fmt.println("  -> Sent SELL AAPL 100@110.00")
    
    // Flush
    n, ok = encode_flush(buf[:])
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    fmt.println("  -> Sent FLUSH")
    
    // Drain responses
    if !drain_responses(fd, stats, 2) {
        return false
    }
    
    return true
}

// Scenario 2: Buy and sell that fully match
scenario_buy_sell_full_match :: proc(fd: os.Handle, stats: ^Scenario_Stats) -> bool {
    fmt.println("Scenario 2: Buy/Sell full match")
    
    buf: [64]u8
    
    // Send BUY @ 100
    n, ok := encode_new_order(buf[:], 1, "AAPL", 10000, 100, .Buy, 1)
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    stats.orders_sent += 1
    fmt.println("  -> Sent BUY  AAPL 100@100.00")
    
    // Send SELL @ 100 (matches!)
    n, ok = encode_new_order(buf[:], 2, "AAPL", 10000, 100, .Sell, 1)
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    stats.orders_sent += 1
    fmt.println("  -> Sent SELL AAPL 100@100.00")
    
    // Expect: 2 ACKs + 1 Trade (possibly 2 trades for buyer+seller)
    if !drain_responses(fd, stats, 2) {
        return false
    }
    
    return true
}

// Scenario 3: Place order then cancel it
scenario_buy_then_cancel :: proc(fd: os.Handle, stats: ^Scenario_Stats) -> bool {
    fmt.println("Scenario 3: Buy then Cancel")
    
    buf: [64]u8
    
    // Send BUY
    n, ok := encode_new_order(buf[:], 1, "AAPL", 10000, 100, .Buy, 1)
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    stats.orders_sent += 1
    fmt.println("  -> Sent BUY AAPL 100@100.00")
    
    // Wait for ACK
    if !drain_responses(fd, stats, 1) {
        return false
    }
    
    // Cancel
    n, ok = encode_cancel(buf[:], 1, 1)
    if !ok || !send_frame(fd, buf[:n]) {
        return false
    }
    stats.cancels_sent += 1
    fmt.println("  -> Sent CANCEL order_id=1")
    
    // Wait for Cancel ACK
    if !drain_responses(fd, stats, 1) {
        return false
    }
    
    return true
}

// Scenario 20-22: Stress test single symbol
scenario_stress_single :: proc(fd: os.Handle, stats: ^Scenario_Stats, order_count: int) -> bool {
    fmt.printf("Scenario: Stress test %d orders (single symbol)\n", order_count)
    fmt.println("  Expecting", order_count/2, "trades")
    
    buf: [64]u8
    half := order_count / 2
    price := u32(10000)  // $100.00
    
    // Send all BUYs first
    fmt.println("  -> Sending", half, "BUY orders...")
    for i in 0..<half {
        n, ok := encode_new_order(buf[:], 1, "AAPL", price, 100, .Buy, u32(i + 1))
        if !ok || !send_frame(fd, buf[:n]) {
            fmt.println("  !! Failed at BUY order", i)
            return false
        }
        stats.orders_sent += 1
    }
    
    // Send all SELLs (will match)
    fmt.println("  -> Sending", half, "SELL orders...")
    for i in 0..<half {
        n, ok := encode_new_order(buf[:], 2, "AAPL", price, 100, .Sell, u32(i + 1))
        if !ok || !send_frame(fd, buf[:n]) {
            fmt.println("  !! Failed at SELL order", i)
            return false
        }
        stats.orders_sent += 1
    }
    
    // Drain all responses
    fmt.println("  -> Waiting for responses...")
    if !drain_responses(fd, stats, order_count) {
        return false
    }
    
    return true
}

// Scenario 30-31: Stress test dual symbols (for dual-processor routing)
scenario_stress_dual :: proc(fd: os.Handle, stats: ^Scenario_Stats, order_count: int) -> bool {
    fmt.printf("Scenario: Stress test %d orders (dual symbol AAPL/TSLA)\n", order_count)
    fmt.println("  Expecting", order_count/2, "trades total")
    
    buf: [64]u8
    quarter := order_count / 4
    price := u32(10000)
    
    symbols := [2]string{"AAPL", "TSLA"}
    
    // Interleave orders across both symbols for maximum parallelism
    fmt.println("  -> Sending", quarter * 2, "BUY orders across AAPL/TSLA...")
    for i in 0..<quarter {
        for sym_idx in 0..<2 {
            n, ok := encode_new_order(
                buf[:], 
                u32(sym_idx + 1),      // user_id per symbol
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
        }
    }
    
    fmt.println("  -> Sending", quarter * 2, "SELL orders across AAPL/TSLA...")
    for i in 0..<quarter {
        for sym_idx in 0..<2 {
            n, ok := encode_new_order(
                buf[:], 
                u32(sym_idx + 10),     // different user_id for sellers
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
        }
    }
    
    fmt.println("  -> Waiting for responses...")
    if !drain_responses(fd, stats, order_count) {
        return false
    }
    
    return true
}

// ============================================================================
// Response handling
// ============================================================================

// Drain expected number of ACKs (trades may generate extra messages)
drain_responses :: proc(fd: os.Handle, stats: ^Scenario_Stats, min_expected: int) -> bool {
    recv_buf: [64 * 1024]u8
    received := 0
    
    // Keep reading until we've gotten at least min_expected ACKs
    // or we get a read timeout/error
    for stats.acks_received + stats.cancel_acks + stats.rejects < u64(min_expected) {
        payload_len, ok := recv_frame(fd, recv_buf[:])
        if !ok {
            // Could be timeout or disconnect
            if received > 0 {
                return true  // Got some responses, might be done
            }
            return false
        }
        
        out: Output_Msg
        _, decode_ok := decode_output(recv_buf[:payload_len], &out)
        if !decode_ok {
            fmt.println("  !! Failed to decode response")
            continue
        }
        
        received += 1
        
        switch out.typ {
        case .Ack:
            stats.acks_received += 1
        case .Cancel_Ack:
            stats.cancel_acks += 1
        case .Trade:
            stats.trades_received += 1
        case .Reject:
            stats.rejects += 1
            sym := symbol_to_string(out.symbol[:])
            fmt.println("  !! REJECT:", sym, "reason=", out.reason)
        case .Top_Of_Book:
            // Informational, don't count
        }
    }
    
    // Continue draining any remaining messages (trades come after ACKs)
    drain_remaining(fd, stats)
    
    return true
}

// Non-blocking drain of any remaining messages
drain_remaining :: proc(fd: os.Handle, stats: ^Scenario_Stats) {
    recv_buf: [64 * 1024]u8
    
    // Try to read a few more times to catch trailing trades
    for attempt in 0..<100 {
        payload_len, ok := recv_frame(fd, recv_buf[:])
        if !ok {
            break
        }
        
        out: Output_Msg
        _, decode_ok := decode_output(recv_buf[:payload_len], &out)
        if !decode_ok {
            continue
        }
        
        switch out.typ {
        case .Ack:
            stats.acks_received += 1
        case .Cancel_Ack:
            stats.cancel_acks += 1
        case .Trade:
            stats.trades_received += 1
        case .Reject:
            stats.rejects += 1
        case .Top_Of_Book:
            // skip
        }
    }
}
