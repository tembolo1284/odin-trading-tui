package client

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

print_usage :: proc(progname: string) {
    fmt.printf("Usage: %s <host> <port> [scenario] [options]\n\n", progname)
    fmt.println("Options:")
    fmt.println("  --tcp           Force TCP (default: auto)")
    fmt.println("  --udp           Force UDP")
    fmt.println("  --binary        Force binary protocol")
    fmt.println("  --csv           Force CSV protocol")
    fmt.println("  --quiet         Suppress non-essential output")
    fmt.println("  --verbose       Verbose output")
    fmt.println("  --danger-burst  Allow burst scenarios")
    fmt.println("\nExamples:")
    fmt.printf("  %s localhost 1234                    # Interactive mode\n", progname)
    fmt.printf("  %s localhost 1234 2 --tcp            # Scenario 2 over TCP\n", progname)
    fmt.printf("  %s localhost 1234 --udp --csv        # UDP with CSV\n", progname)
}

main :: proc() {
    args := os.args
    
    if len(args) < 3 {
        print_usage(len(args) > 0 ? args[0] : "client")
        os.exit(1)
    }
    
    host := args[1]
    port_str := args[2]
    
    port, ok := strconv.parse_uint(port_str, 10)
    if !ok || port == 0 || port > 65535 {
        fmt.eprintf("Invalid port: %s\n", port_str)
        os.exit(1)
    }
    
    config: Client_Config
    config_init(&config)
    config_set_host(&config, host)
    config.port = u16(port)
    
    scenario_id := 0
    
    for i := 3; i < len(args); i += 1 {
        arg := args[i]
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
        } else if scenario_id == 0 {
            if id, ok := strconv.parse_int(arg, 10); ok && id > 0 {
                scenario_id = int(id)
                config.mode = .Scenario
                config.scenario_id = scenario_id
            }
        }
    }
    
    client: Engine_Client
    engine_client_init(&client, &config)
    
    if !engine_client_connect(&client) {
        fmt.eprintln("Failed to connect")
        os.exit(1)
    }
    
    if !config.quiet {
        fmt.println("=== Matching Engine Client ===")
        fmt.printf("Host:     %s:%d\n", host, port)
        fmt.printf("Transport: %s\n", transport_type_str(engine_client_get_transport(&client)))
        fmt.printf("Encoding:  %s\n", encoding_type_str(engine_client_get_encoding(&client)))
    }
    
    if scenario_id > 0 {
        result: Scenario_Result
        scenario_run(&client, scenario_id, config.danger_burst, &result)
        
        if config.transport == .TCP {
            opts: Interactive_Options
            interactive_options_init(&opts)
            opts.danger_burst = config.danger_burst
            interactive_run(&client, &opts)
        }
    } else {
        opts: Interactive_Options
        interactive_options_init(&opts)
        opts.danger_burst = config.danger_burst
        interactive_run(&client, &opts)
    }
    
    engine_client_disconnect(&client)
    
    if !config.quiet {
        fmt.println("\nDisconnected.")
    }
}
