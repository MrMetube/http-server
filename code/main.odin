#+vet explicit-allocators
package main

import "core:fmt"
import os "core:os/os2"
import "core:net"

Server :: struct {
    valid: bool,
    
    socket: net.TCP_Socket,
}

main :: proc () {
    server := begin_server("localhost:42069")
    defer end_server(server)
    
    if server.valid {
        for {
            client, client_source, accept_error := net.accept_tcp(server.socket)
            if accept_error != nil {
                end, _ := net.bound_endpoint(server.socket)
                fmt.printf("Error: failed to accept a client tcp on '%v': %v\n", net.endpoint_to_string(end, context.temp_allocator), accept_error)
                os.exit(1)
            }
            
            fmt.printf("Connection accepted by %v with source %v\n", client, client_source)
            
            reader: SocketReadContext
            reader.socket = client
            
            r := request_parse_from_socket(&reader)
            
            fmt.printf("------------------------------\nConnection closed with %v and source %v\n", client, client_source)
            
            test_request_parsing()
        }
    }
}

////////////////////////////////////////////////

begin_server :: proc (host_colon_port: string) -> Server {
    result: Server
    
    endpoint, resolve_error := net.resolve_ip4(host_colon_port)
    if resolve_error != nil {
        fmt.printf("Error: failed to resolve endpoint '%v': %v\n", host_colon_port, resolve_error)
        os.exit(1)
    } else {
        server_socket, listen_error := net.listen_tcp(endpoint)
        
        if listen_error != nil {
            fmt.printf("Error: failed to create and listen on '%v': %v\n", host_colon_port, listen_error)
            os.exit(1)
        } else {
            result.valid = true
            result.socket = server_socket
            fmt.printf("Start listening on %v\n", host_colon_port)
        }
    }
    
    return result
}

end_server :: proc (server: Server) {
    net.close(server.socket)
}