package client

import "core:fmt"
import "core:os"
import "core:strconv"

// Default ports
DEFAULT_TCP_PORT :: 1234
DEFAULT_UDP_PORT :: 1235

print_usage :: proc(progname: string) {
    fmt.printf("Usage: %s [options] [host] [port] [scenario]\n\n", progname)
    fmt.println("All arguments are optional with sensible defaults.")
    fmt.println("\nDefaults:")
    fmt.println("  host       localhost")
    fmt.println("  port       1234 (TCP) or 1235 (UDP)")
    fmt.println("  transport  TCP")
    fmt.println("  encoding   Binary")
    fmt.println("\nOptions:")
    fmt.println("  --tcp           Use TCP transport (default)")
    fmt.println("  --udp           Use UDP transport")
    fmt.println("  --binary        Use binary protocol (default)")
    fmt.println("  --csv           Use CSV protocol")
    fmt.println("  --quiet         Suppress non-essential output")
    fmt.println("  --verbose       Verbose output")
    fmt.println("  --danger-burst  Allow burst scenarios")
    fmt.println("  -h, --help      Show this help")
    fmt.println("\nExamples:")
    fmt.printf("  %s                        # Interactive on localhost:1234\n", progname)
    fmt.printf("  %s 2                       # Run scenario 2\n", progname)
    fmt.printf("  %s myhost                  # Connect to myhost:1234\n", progname)
    fmt.printf("  %s myhost 5000             # Connect to myhost:5000\n", progname)
    fmt.printf("  %s myhost 5000 2           # Run scenario 2 on myhost:5000\n", progname)
    fmt.printf("  %s --udp 2                 # Scenario 2 over UDP on port 1235\n", progname)
    fmt.printf("  %s --csv                   # Interactive with CSV encoding\n", progname)
}

main :: proc() {
    args := os.args
    progname := len(args) > 0 ? args[0] : "client"
    
    // Defaults
    host := "localhost"
    port: u16 = 0  // Will be set based on transport
    scenario_id := 0
    explicit_port := false
    
    config: Client_Config
    config_init(&config)
    config.transport = .TCP    // Default to TCP
    config.encoding = .Binary  // Default to Binary
    
    // Parse arguments
    positional_count := 0
    
    for i := 1; i < len(args); i += 1 {
        arg := args[i]
        
        // Check for flags first
        if arg == "--tcp" {
            config.transport = .TCP
        } else if arg == "--udp" {
            config.transport = .UDP
        } else if arg == "--binary" {
            config.encoding = .Binary
        } else if arg == "--csv" {
            config.encoding = .CSV
        } else if arg == "--quiet" {
            config.quiet = true
        } else if arg == "--verbose" {
            config.verbose = true
        } else if arg == "--danger-burst" {
            config.danger_burst = true
        } else if arg == "-h" || arg == "--help" {
            print_usage(progname)
            os.exit(0)
        } else if len(arg) > 0 && arg[0] == '-' {
            fmt.eprintf("Unknown option: %s\n", arg)
            print_usage(progname)
            os.exit(1)
        } else {
            // Positional argument
            if num, num_ok := strconv.parse_int(arg); num_ok && num > 0 {
                if positional_count == 0 && num <= 50 {
                    // First positional, small number = scenario
                    scenario_id = int(num)
                } else if positional_count == 0 && num > 50 && num <= 65535 {
                    // First positional, large number = port
                    port = u16(num)
                    explicit_port = true
                    positional_count += 1
                } else if positional_count == 1 && num <= 65535 {
                    // Second positional after host = port or scenario
                    if num <= 50 && !explicit_port {
                        scenario_id = int(num)
                    } else {
                        port = u16(num)
                        explicit_port = true
                        positional_count += 1
                    }
                } else if num <= 50 {
                    // Must be scenario
                    scenario_id = int(num)
                } else {
                    fmt.eprintf("Invalid argument: %s\n", arg)
                    os.exit(1)
                }
            } else {
                // Not a number = hostname
                if positional_count == 0 {
                    host = arg
                    positional_count += 1
                } else {
                    fmt.eprintf("Unexpected argument: %s\n", arg)
                    os.exit(1)
                }
            }
        }
    }
    
    // Set default port based on transport if not specified
    if port == 0 {
        port = config.transport == .UDP ? DEFAULT_UDP_PORT : DEFAULT_TCP_PORT
    }
    
    config_set_host(&config, host)
    config.port = port
    
    if scenario_id > 0 {
        config.mode = .Scenario
        config.scenario_id = scenario_id
    }
    
    // Connect
    client: Engine_Client
    engine_client_init(&client, &config)
    
    if !engine_client_connect(&client) {
        fmt.eprintln("Failed to connect")
        os.exit(1)
    }
    
    if !config.quiet {
        fmt.println("=== Matching Engine Client ===")
        fmt.printf("Host:      %s:%d\n", host, port)
        fmt.printf("Transport: %s\n", transport_type_str(engine_client_get_transport(&client)))
        fmt.printf("Encoding:  %s\n", encoding_type_str(engine_client_get_encoding(&client)))
        if scenario_id > 0 {
            fmt.printf("Scenario:  %d\n", scenario_id)
        }
        fmt.println()
    }
    
    // Run scenario or interactive mode
    if scenario_id > 0 {
        result: Scenario_Result
        if !scenario_run(&client, scenario_id, config.danger_burst, &result) {
            fmt.eprintln("Scenario failed or not found")
        }
    } else {
        opts: Interactive_Options
        interactive_options_init(&opts)
        opts.danger_burst = config.danger_burst
        interactive_run(&client, &opts)
    }
    
    engine_client_disconnect(&client)
    
    if !config.quiet {
        fmt.println("Disconnected.")
    }
}
