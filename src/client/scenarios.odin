package client

import "core:fmt"
import "core:time"

Scenario_Category :: enum {
    Basic,
    Stress,
    Matching,
    Multi_Symbol,
}

Scenario_Info :: struct {
    id:          int,
    name:        string,
    description: string,
    category:    Scenario_Category,
    order_count: u32,
}

Scenario_Result :: struct {
    orders_sent:        u32,
    orders_failed:      u32,
    responses_received: u32,
    trades_executed:    u32,
    start_time_ns:      i64,
    end_time_ns:        i64,
    total_time_ns:      u64,
    min_latency_ns:     u64,
    avg_latency_ns:     u64,
    max_latency_ns:     u64,
    orders_per_sec:     f64,
    proc0_orders:       u32,
    proc1_orders:       u32,
}

SCENARIOS := []Scenario_Info{
    {1,  "simple-orders",   "Simple orders (no match)",           .Basic,    3},
    {2,  "matching-trade",  "Matching trade execution",           .Basic,    2},
    {3,  "cancel-order",    "Cancel order",                       .Basic,    2},
    {10, "stress-1k",       "Stress: 1K orders",                  .Stress,   1000},
    {11, "stress-10k",      "Stress: 10K orders",                 .Stress,   10000},
    {20, "match-1k",        "Matching: 1K pairs",                 .Matching, 2000},
    {21, "match-10k",       "Matching: 10K pairs",                .Matching, 20000},
    {22, "match-100k",      "Matching: 100K pairs",               .Matching, 200000},
    {23, "match-1m",        "Matching: 1M pairs",                 .Matching, 2000000},
    {24, "match-10m",       "Matching: 10M pairs",                .Matching, 20000000},
}

Callback_Context :: struct {
    result:  ^Scenario_Result,
    verbose: bool,
}

scenario_response_counter :: proc(msg: ^Output_Msg, user_data: rawptr) {
    ctx := cast(^Callback_Context)user_data
    if ctx.result != nil {
        ctx.result.responses_received += 1
        if msg.type == .Trade {
            ctx.result.trades_executed += 1
        }
    }
    if ctx.verbose {
        switch msg.type {
        case .Ack:
            ack := msg.data.(Ack_Msg)
            fmt.printf("[RECV] A, %s, %d, %d\n", symbol_to_string(ack.symbol[:]), ack.user_id, ack.user_order_id)
        case .Cancel_Ack:
            cack := msg.data.(Cancel_Ack_Msg)
            fmt.printf("[RECV] C, %s, %d, %d\n", symbol_to_string(cack.symbol[:]), cack.user_id, cack.user_order_id)
        case .Trade:
            t := msg.data.(Trade_Msg)
            fmt.printf("[RECV] T, %s, %d, %d, %d, %d, %d, %d\n",
                symbol_to_string(t.symbol[:]), t.user_id_buy, t.user_order_id_buy,
                t.user_id_sell, t.user_order_id_sell, t.price, t.quantity)
        case .Top_Of_Book:
            tob := msg.data.(Top_Of_Book_Msg)
            if tob.price == 0 {
                fmt.printf("[RECV] B, %s, %c, -, -\n", symbol_to_string(tob.symbol[:]), side_to_char(tob.side))
            } else {
                fmt.printf("[RECV] B, %s, %c, %d, %d\n",
                    symbol_to_string(tob.symbol[:]), side_to_char(tob.side), tob.price, tob.total_quantity)
            }
        }
    }
}

init_result :: proc(result: ^Scenario_Result) {
    result^ = {}
}

finalize_result :: proc(result: ^Scenario_Result, client: ^Engine_Client) {
    result.end_time_ns = time.now()._nsec
    result.total_time_ns = u64(result.end_time_ns - result.start_time_ns)
    result.min_latency_ns = engine_client_get_min_latency_ns(client)
    result.avg_latency_ns = engine_client_get_avg_latency_ns(client)
    result.max_latency_ns = engine_client_get_max_latency_ns(client)
    if result.total_time_ns > 0 {
        seconds := f64(result.total_time_ns) / 1e9
        result.orders_per_sec = f64(result.orders_sent) / seconds
    }
}

sleep_ms :: proc(ms: int) {
    time.sleep(time.Duration(ms) * time.Millisecond)
}

drain_responses :: proc(client: ^Engine_Client, initial_delay_ms: int) {
    sleep_ms(initial_delay_ms)
    empty_count := 0
    for empty_count < 5 {
        count := engine_client_recv_all(client, 50)
        if count == 0 {
            empty_count += 1
            sleep_ms(20)
        } else {
            empty_count = 0
        }
    }
}

scenario_get_info :: proc(id: int) -> ^Scenario_Info {
    for &s in SCENARIOS {
        if s.id == id { return &s }
    }
    return nil
}

scenario_is_valid :: proc(id: int) -> bool {
    return scenario_get_info(id) != nil
}

scenario_print_list :: proc() {
    fmt.println("Available scenarios:\n")
    fmt.println("Basic:")
    for s in SCENARIOS { if s.category == .Basic { fmt.printf("  %-3d - %s\n", s.id, s.description) } }
    fmt.println("\nStress:")
    for s in SCENARIOS { if s.category == .Stress { fmt.printf("  %-3d - %s\n", s.id, s.description) } }
    fmt.println("\nMatching:")
    for s in SCENARIOS { if s.category == .Matching { fmt.printf("  %-3d - %s\n", s.id, s.description) } }
}

scenario_print_result :: proc(result: ^Scenario_Result) {
    fmt.println("\n=== Scenario Results ===\n")
    fmt.printf("Orders sent: %d, Failed: %d, Responses: %d, Trades: %d\n",
        result.orders_sent, result.orders_failed, result.responses_received, result.trades_executed)
    fmt.printf("Time: %.3f sec, Rate: %.0f orders/sec\n",
        f64(result.total_time_ns) / 1e9, result.orders_per_sec)
    if result.min_latency_ns > 0 {
        fmt.printf("Latency - Min: %.3f us, Avg: %.3f us, Max: %.3f us\n",
            f64(result.min_latency_ns)/1000, f64(result.avg_latency_ns)/1000, f64(result.max_latency_ns)/1000)
    }
}

// =============================================================================
// Basic Scenarios
// =============================================================================

scenario_simple_orders :: proc(client: ^Engine_Client, result: ^Scenario_Result) -> bool {
    fmt.println("=== Scenario 1: Simple Orders ===\n")
    init_result(result)
    result.start_time_ns = time.now()._nsec
    ctx := Callback_Context{result, true}
    engine_client_set_response_callback(client, scenario_response_counter, &ctx)
    
    fmt.println("Sending: BUY IBM 50@100")
    if engine_client_send_order(client, "IBM", 100, 50, .Buy, 0) > 0 { result.orders_sent += 1 }
    drain_responses(client, 100)
    
    fmt.println("Sending: SELL IBM 50@105")
    if engine_client_send_order(client, "IBM", 105, 50, .Sell, 0) > 0 { result.orders_sent += 1 }
    drain_responses(client, 100)
    
    fmt.println("Sending: FLUSH")
    engine_client_send_flush(client)
    result.orders_sent += 1
    drain_responses(client, 200)
    
    finalize_result(result, client)
    return true
}

scenario_matching_trade :: proc(client: ^Engine_Client, result: ^Scenario_Result) -> bool {
    fmt.println("=== Scenario 2: Matching Trade ===\n")
    init_result(result)
    result.start_time_ns = time.now()._nsec
    ctx := Callback_Context{result, true}
    engine_client_set_response_callback(client, scenario_response_counter, &ctx)
    
    fmt.println("Sending: BUY IBM 50@100")
    if engine_client_send_order(client, "IBM", 100, 50, .Buy, 0) > 0 { result.orders_sent += 1 }
    drain_responses(client, 100)
    
    fmt.println("Sending: SELL IBM 50@100 (should match!)")
    if engine_client_send_order(client, "IBM", 100, 50, .Sell, 0) > 0 { result.orders_sent += 1 }
    drain_responses(client, 150)
    
    finalize_result(result, client)
    return true
}

scenario_cancel_order :: proc(client: ^Engine_Client, result: ^Scenario_Result) -> bool {
    fmt.println("=== Scenario 3: Cancel Order ===\n")
    init_result(result)
    result.start_time_ns = time.now()._nsec
    ctx := Callback_Context{result, true}
    engine_client_set_response_callback(client, scenario_response_counter, &ctx)
    
    fmt.println("Sending: BUY IBM 50@100")
    oid := engine_client_send_order(client, "IBM", 100, 50, .Buy, 0)
    if oid > 0 { result.orders_sent += 1 }
    drain_responses(client, 100)
    
    fmt.printf("Sending: CANCEL order %d\n", oid)
    engine_client_send_cancel(client, oid)
    drain_responses(client, 100)
    
    finalize_result(result, client)
    return true
}

// =============================================================================
// Stress Test Scenarios
// =============================================================================

scenario_stress_test :: proc(client: ^Engine_Client, count: u32, result: ^Scenario_Result) -> bool {
    fmt.printf("=== Stress Test: %d Orders ===\n\n", count)
    init_result(result)
    result.start_time_ns = time.now()._nsec
    ctx := Callback_Context{result, false}
    engine_client_set_response_callback(client, scenario_response_counter, &ctx)
    
    // Clear any existing orders
    engine_client_send_flush(client)
    drain_responses(client, 100)
    result.responses_received = 0
    
    progress_interval := count / 20
    if progress_interval == 0 { progress_interval = 1 }
    
    // Batch size for interleaving sends and receives
    batch_size: u32 = 50
    if count < 500 { batch_size = 10 }
    
    i: u32 = 0
    for i < count {
        // Send a batch of orders
        batch_end := i + batch_size
        if batch_end > count { batch_end = count }
        
        for j := i; j < batch_end; j += 1 {
            price := 100 + (j % 100)
            if engine_client_send_order(client, "IBM", price, 10, .Buy, 0) > 0 {
                result.orders_sent += 1
            } else {
                result.orders_failed += 1
            }
        }
        
        // Receive responses for this batch
        engine_client_recv_all(client, 50)
        
        i = batch_end
        
        // Progress update
        if i > 0 && i % progress_interval == 0 {
            pct := (i * 100) / count
            fmt.printf("  %d%% (sent=%d, acks=%d)\n", pct, result.orders_sent, result.responses_received)
        }
    }
    
    fmt.println("\nFlushing and draining...")
    engine_client_send_flush(client)
    drain_responses(client, 500)
    
    finalize_result(result, client)
    scenario_print_result(result)
    
    if result.responses_received >= result.orders_sent {
        fmt.printf("✓ All %d orders acknowledged!\n\n", result.orders_sent)
    } else {
        fmt.printf("⚠ Sent %d orders, got %d acks\n\n", result.orders_sent, result.responses_received)
    }
    
    return true
}

// =============================================================================
// Matching Stress Scenarios
// =============================================================================

scenario_matching_stress :: proc(client: ^Engine_Client, pairs: u32, result: ^Scenario_Result) -> bool {
    fmt.printf("=== Matching Stress: %d Pairs ===\n\n", pairs)
    init_result(result)
    result.start_time_ns = time.now()._nsec
    ctx := Callback_Context{result, false}
    engine_client_set_response_callback(client, scenario_response_counter, &ctx)
    
    // Clear any existing orders
    engine_client_send_flush(client)
    drain_responses(client, 200)
    result.responses_received = 0
    
    progress_interval := pairs / 20
    if progress_interval == 0 { progress_interval = 1 }
    
    // For smaller tests, wait for each trade
    // For larger tests, batch more aggressively
    batch_size: u32 = 1
    recv_timeout := 100
    if pairs >= 10000 {
        batch_size = 50
        recv_timeout = 50
    } else if pairs >= 1000 {
        batch_size = 10
        recv_timeout = 75
    }
    
    i: u32 = 0
    for i < pairs {
        // Send a batch of buy/sell pairs
        batch_end := i + batch_size
        if batch_end > pairs { batch_end = pairs }
        
        for j := i; j < batch_end; j += 1 {
            price := 100 + (j % 50)
            
            // Send buy
            if engine_client_send_order(client, "IBM", price, 10, .Buy, 0) > 0 { 
                result.orders_sent += 1 
            } else {
                result.orders_failed += 1
            }
            
            // Send matching sell
            if engine_client_send_order(client, "IBM", price, 10, .Sell, 0) > 0 { 
                result.orders_sent += 1 
            } else {
                result.orders_failed += 1
            }
        }
        
        // Receive responses for this batch (acks + trades)
        engine_client_recv_all(client, recv_timeout)
        
        i = batch_end
        
        // Progress update
        if i > 0 && i % progress_interval == 0 {
            pct := (i * 100) / pairs
            fmt.printf("  %d%% | pairs=%d, trades=%d\n", pct, i, result.trades_executed)
        }
    }
    
    fmt.println("\nDraining remaining responses...")
    drain_responses(client, 1000)
    
    finalize_result(result, client)
    scenario_print_result(result)
    
    if result.trades_executed >= pairs {
        fmt.printf("✓ All %d trades executed!\n\n", pairs)
    } else {
        fmt.printf("⚠ Expected %d trades, got %d (%.1f%%)\n\n", 
            pairs, result.trades_executed, f64(result.trades_executed) * 100.0 / f64(pairs))
    }
    
    return true
}

// =============================================================================
// Scenario Runner
// =============================================================================

scenario_run :: proc(client: ^Engine_Client, id: int, danger_burst: bool, result: ^Scenario_Result) -> bool {
    info := scenario_get_info(id)
    if info == nil {
        fmt.printf("Unknown scenario: %d\n\n", id)
        scenario_print_list()
        return false
    }
    
    // Check for dangerous scenarios
    if info.order_count > 100000 && !danger_burst {
        fmt.printf("Scenario %d sends %d orders. Use --danger-burst to enable.\n", 
            id, info.order_count)
        return false
    }
    
    engine_client_reset_stats(client)
    engine_client_reset_order_id(client, 1)
    
    switch id {
    case 1:  return scenario_simple_orders(client, result)
    case 2:  return scenario_matching_trade(client, result)
    case 3:  return scenario_cancel_order(client, result)
    case 10: return scenario_stress_test(client, 1000, result)
    case 11: return scenario_stress_test(client, 10000, result)
    case 20: return scenario_matching_stress(client, 1000, result)
    case 21: return scenario_matching_stress(client, 10000, result)
    case 22: return scenario_matching_stress(client, 100000, result)
    case 23: return scenario_matching_stress(client, 1000000, result)
    case 24: return scenario_matching_stress(client, 10000000, result)
    case:
        fmt.printf("Scenario %d not implemented\n", id)
        return false
    }
}
