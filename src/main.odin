package main

import "core:fmt"
import "core:os"
import "core:net"
import "core:strconv"

import "client"

// ============================================================================
// Matching Engine Test Client
// ============================================================================

DEFAULT_HOST :: "127.0.0.1"
DEFAULT_PORT :: "1234"

main :: proc() {
    fmt.println("╔═══════════════════════════════════════╗")
    fmt.println("║   Odin Matching Engine Test Client    ║")
    fmt.println("╚═══════════════════════════════════════╝")
    fmt.println()

    // Parse command line args
    args := os.args
    
    if len(args) < 2 {
        print_usage()
        return
    }
    
    // Parse scenario number
    scenario_num, ok := strconv.parse_int(args[1])
    if !ok {
        fmt.println("Error: Invalid scenario number:", args[1])
        print_usage()
        return
    }
    
    // Optional host:port
    host := DEFAULT_HOST
    port := DEFAULT_PORT
    if len(args) >= 3 {
        host = args[2]
    }
    if len(args) >= 4 {
        port = args[3]
    }
    
    // Connect
    endpoint_str := fmt.tprintf("%s:%s", host, port)
    fmt.println("Connecting to", endpoint_str, "...")
    
    ep, ep_ok := net.parse_endpoint(endpoint_str)
    if !ep_ok {
        fmt.println("Error: Failed to parse endpoint:", endpoint_str)
        return
    }
    
    sock, conn_err := net.dial_tcp(ep)
    if conn_err != nil {
        fmt.println("Error: Connection failed:", conn_err)
        return
    }
    defer net.close(sock)
    
    fmt.println("Connected!")
    fmt.println()
    
    // Get raw file descriptor for our framing functions
    fd := socket_to_handle(sock)
    
    // Run scenario
    scenario := client.Scenario(scenario_num)
    stats, success := client.run_scenario(fd, scenario)
    
    fmt.println()
    if success {
        fmt.println("✓ Scenario completed successfully")
    } else {
        fmt.println("✗ Scenario failed")
    }
    
    client.print_stats(&stats)
}

// ============================================================================
// Helpers
// ============================================================================

print_usage :: proc() {
    fmt.println("Usage: test_client <scenario> [host] [port]")
    fmt.println()
    fmt.println("Scenarios:")
    fmt.println("  1   Buy/Sell no match + Flush")
    fmt.println("  2   Buy/Sell full match")
    fmt.println("  3   Buy then Cancel")
    fmt.println()
    fmt.println("  20  Stress: 2,000 orders -> 1,000 trades (single symbol)")
    fmt.println("  21  Stress: 20,000 orders -> 10,000 trades (single symbol)")
    fmt.println("  22  Stress: 200,000 orders -> 100,000 trades (single symbol)")
    fmt.println()
    fmt.println("  30  Stress: 2,000 orders (dual symbol AAPL/TSLA)")
    fmt.println("  31  Stress: 20,000 orders (dual symbol AAPL/TSLA)")
    fmt.println()
    fmt.println("Examples:")
    fmt.println("  ./test_client 1")
    fmt.println("  ./test_client 20 192.168.1.100 1234")
}

// Convert net.TCP_Socket to os.Handle for our framing I/O
socket_to_handle :: proc(sock: net.TCP_Socket) -> os.Handle {
    // net.TCP_Socket is just a wrapper around the fd
    return os.Handle(sock)
}
