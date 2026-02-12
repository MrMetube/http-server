#+vet explicit-allocators
package main

import "core:fmt"
import os "core:os/os2"
import "core:mem"
import "core:net"
import "core:strings"

Server :: struct {
    valid: bool,
    
    socket: net.TCP_Socket,
}

main :: proc () {
    server := begin_server("localhost:42069")
    defer end_server(server)
    
    if server.valid {
        request_backing := make([] u8, 512 * Megabyte, context.allocator)
        request_arena: mem.Arena
        mem.arena_init(&request_arena, request_backing)
        request_allocator := mem.arena_allocator(&request_arena)
        
        for {
            free_all(request_allocator)
            
            // @todo(viktor): handle multiple connections
            client, client_source, accept_error := net.accept_tcp(server.socket)
            if accept_error == nil {
                fmt.printf("Connection accepted by %v with source %v\n", client, client_source)
                
                reader := socket_reader_make(client)
                r: Request
                request_init(&r, request_allocator)
                // @todo(viktor): just do upto .request_line and let handler so the rest, or let handler specify this
                request_parse_from_socket(&r, .body, &reader)
                fmt.printf("Received:\n%v\n", r)
                
                sb := strings.builder_make(request_allocator)
                
                content: string
                code: ResponceCode
                headers := make_headers(request_allocator)
                
                switch r.request_target {
                case "/yourproblem":
                    code = .Bad_Request
                    content = `
<html>
  <head>
    <title>400 Bad Request</title>
  </head>
  <body>
    <h1>Bad Request</h1>
    <p>Your request honestly kinda sucked.</p>
  </body>
</html>
`

                case "/myproblem":
                    code = .Internal_Server_Error
                    content = `
<html>
  <head>
    <title>500 Internal Server Error</title>
  </head>
  <body>
    <h1>Internal Server Error</h1>
    <p>Okay, you know what? This one is on me.</p>
  </body>
</html>
`
            
                case:
                    code = .OK
                    content = `
<html>
  <head>
    <title>200 OK</title>
  </head>
  <body>
    <h1>Success!</h1>
    <p>Your request was an absolute banger.</p>
  </body>
</html>
`
                }
                
                get_default_headers(&headers, len(content))
                
                write_response_line(&sb, code)
                write_headers(&sb, &headers)
                write_body(&sb, content)
                
                net.send_tcp(client, sb.buf[:])
                
                // test_request_parsing()
                
                fmt.printf("Connection closed with %v and source %v\n", client, client_source)
            } else {
                end, _ := net.bound_endpoint(server.socket)
                fmt.printf("Error: failed to accept a client tcp on '%v': %v\n", net.endpoint_to_string(end, request_allocator), accept_error)
            }
            
            net.close(client)
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