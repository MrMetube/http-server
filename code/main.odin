#+vet explicit-allocators
package main

import "core:fmt"
import os "core:os/os2"
import "core:mem"
import "core:crypto/sha2"
import "core:net"
import "core:strings"
import "core:strconv"

Server :: struct {
    valid: bool,
    
    socket: net.TCP_Socket,
}

main :: proc () {
    server := begin_server("localhost:42069")
    defer end_server(server)
    
    if server.valid {
        request_backing := make([] u8, 1 * Gigabyte, context.allocator)
        request_arena: mem.Arena
        mem.arena_init(&request_arena, request_backing)
        request_allocator := mem.arena_allocator(&request_arena)
        
        for {
            free_all(request_allocator)
            
            // @todo(viktor): handle multiple connections
            client, client_source, accept_error := net.accept_tcp(server.socket)
            if accept_error == nil {
                fmt.printf("Connection accepted by %v with source %v\n", client, client_source)
                
                reader := socket_reader_make(client, make([]u8, 8, request_allocator))
                
                r: Request
                request_init(&r, request_allocator)
                
                request_parse_from_socket(&r, &reader, .request_line)
                // fmt.printf("Received:\n%v %v %v\n%v\n\n%v\n", r.method, r.request_target, r.http_version, r.headers, r.body)
                
                sb := strings.builder_make(request_allocator)
                
                response: Response
                response.headers = make_headers(request_allocator)
                
                if is_route(r, "/yourproblem") {
                    request_parse_from_socket(&r, &reader, .body)
                    route_yourproblem(&response)
                    respond_and_close(client, client_source, &sb, &response)
                } else if is_route(r, "/myproblem") {
                    request_parse_from_socket(&r, &reader, .body)
                    route_myproblem(&response)
                    respond_and_close(client, client_source, &sb, &response)
                } else if route_ok, rest := is_route_and_rest(r, "/httpbin"); route_ok {
                    request_parse_from_socket(&r, &reader, .body)
                    httpbin, dial_ok := dial("httpbin.org:80")
                    if !dial_ok do os.exit(1)
                    
                    httpbin_sb := strings.builder_make(request_allocator)
                    route := fmt.aprintf("/%v", rest, allocator = request_allocator)
                    message := make_request(&httpbin_sb, "GET", route, headers="Host: httpbin.org")
                    if !send(httpbin, message) do os.exit(1)
                    
                    
                    response.code = .OK
                    write_response_line(&sb, response.code)
                    
                    httpbin_response: Response
                    response_init(&httpbin_response, request_allocator)
                    
                    httpbin_reader := socket_reader_make(httpbin, make([] u8, 4*Kilobyte, request_allocator))
                    // @todo(viktor): check that all the fields are actually parsed correctly
                    response_parse_from_socket(&httpbin_response, &httpbin_reader, .headers)
                    assert(!httpbin_response.invalid)
                    
                    fmt.println("httpbin_response", httpbin_response)
                    
                    sha_context: sha2.Context_256
                    sha2.init_256(&sha_context)
                    total_count: int
                    
                    x_content_sha := "x-content-sha256"
                    x_content_length := "x-content-length"
                    add_default_headers_chunked(&response.headers)
                    headers_set_lower(&response.headers, "trailers", x_content_sha)
                    headers_set_lower(&response.headers, "trailers", x_content_length)
                    write_headers(&sb, &response.headers)
                    send_and_reset(client, &sb)
                    
                    if content_length, content_lenght_present := headers_get_lower(&httpbin_response.headers, "content-length"); content_lenght_present {
                        // @note(viktor): sized reading - chunked writing
                        response_parse(&httpbin_response, &httpbin_reader, .body)
                        
                        total_count = len(httpbin_response.body)
                        
                        send_chunk(client, &sb, httpbin_response.body)
                        send_chunk(client, &sb, "")
                    } else {
                        // @note(viktor): chunked reading - chunked writing
                        copy_buffer := make_byte_buffer(make([] u8, 4 * Kilobyte, request_allocator))
                        for {
                            if !read_until(&copy_buffer, &httpbin_reader, "\r\n") {
                                // @incomplete handle read error
                            }
                            
                            length_string := buffer_read_all_string_and_reset(&copy_buffer)
                            length_string = trim(length_string)
                            length, ok := strconv.parse_int(length_string, base = 16)
                            if !ok {
                                // @incomplete handle parse error
                            }
                            
                            fmt.sbprintf(&sb, "%x\r\n", length)
                            send_and_reset(client, &sb)
                            
                            // @todo(viktor): this structure is exactly the same as inside read_count. though bool is a pleasent return value, we need to be able to indicate errrors on read AND errors/no space left to write into 
                            // @correctness, all these reads should be a loop IF and only if the size of the read COULD exceed the copy_buffers size, which is true for these chunks
                            remaining := length + len("\r\n")
                            for !read_count(&copy_buffer, &httpbin_reader, remaining) {
                                // @incomplete handle read error
                                content := buffer_read_all_string_and_reset(&copy_buffer)
                                
                                content_length := len(content)-2 // all but the \r\ns
                                total_count += content_length
                                sha2.update(&sha_context, to_bytes(content[:content_length]))
                                send(client, content)
                                
                                remaining -= len(content)
                            }
                            
                            content := buffer_read_all_string_and_reset(&copy_buffer)
                            send(client, content)
                            content_length := len(content)-2 // all but the \r\ns
                            total_count += content_length
                            sha2.update(&sha_context, to_bytes(content[:content_length]))
                            
                            if length == 0 && content == "\r\n" do break
                        }
                    }
                    
                    // @todo(viktor): how do i know that i did it right?
                    hash: [256] u8
                    sha2.final(&sha_context, hash[:])
                    
                    write_headers_key(&sb, x_content_length)
                    fmt.sbprintf(&sb, "%v\r\n", total_count)
                    
                    write_headers_key(&sb, x_content_sha)
                    for b in hash {
                        fmt.sbprintf(&sb, "%02x", b)
                    }
                    fmt.sbprintf(&sb, "\r\n")
                    fmt.sbprintf(&sb, "\r\n")
                    
                    send_and_reset(client, &sb)
                    
                    net.close(httpbin)
                    net.close(client)
                    
                    fmt.printf("Connection closed with %v and source %v\n", client, client_source)
                } else {
                    request_parse_from_socket(&r, &reader, .body)
                    route_any(&response)
                    respond_and_close(client, client_source, &sb, &response)
                }
                
                test_request_parsing()
                
            } else {
                end, _ := net.bound_endpoint(server.socket)
                fmt.printf("Error: failed to accept a client tcp on '%v': %v\n", net.endpoint_to_string(end, request_allocator), accept_error)
                net.close(client)
            }
            
        }
    }
}

////////////////////////////////////////////////

respond_and_close :: proc (client: net.TCP_Socket, client_source: net.Endpoint, sb: ^strings.Builder, response: ^Response) {
    add_default_headers(&response.headers, len(response.body))
    
    write_response_line(sb, response.code)
    write_headers(sb, &response.headers)
    write_body(sb, response.body)
    
    send(client, strings.to_string(sb^))
    
    fmt.printf("Connection closed with %v and source %v\n", client, client_source)
    
    net.close(client)
}

send_chunk :: proc (client: net.TCP_Socket, sb: ^strings.Builder, message: string) {
    fmt.sbprintf(sb, "%x\r\n", len(message))
    send_and_reset(client, sb)
    send(client, message)
    send(client, "\r\n")
}

////////////////////////////////////////////////

make_request :: proc (sb: ^strings.Builder, method: string, route: string, headers:= "", content := "") -> string {
    fmt.sbprintf(sb, "%v %v HTTP/1.1\r\n", method, route)
    if headers != "" {
        fmt.sbprintf(sb, "%v\r\n", headers)
    }
    if content != "" {
        fmt.sbprintf(sb, "Content-Length: %v\r\n\r\n%v", len(content), content)
    } else {
        fmt.sbprintf(sb, "\r\n")
    }
    return strings.to_string(sb^)
}

////////////////////////////////////////////////

dial :: proc (host_and_port: string) -> (net.TCP_Socket, bool) {
    socket, connect_error := net.dial_tcp_from_hostname_and_port_string(host_and_port)
    if connect_error != nil {
        fmt.printf("Error: failed to connect to '%v': %v\n", host_and_port, connect_error)
        return socket, false
    }
    return socket, true
}

send_and_reset :: proc (socket: net.TCP_Socket, sb: ^strings.Builder) -> bool {
    result := send(socket, strings.to_string(sb^))
    strings.builder_reset(sb)
    return result
}

send :: proc (socket: net.TCP_Socket, message: string) -> bool {
    bytes_written, write_error := net.send_tcp(socket, to_bytes(message))
    if write_error != nil {
        fmt.printf("Error: failed to write to '%v': %v\n", address_and_port_from_socket(socket), write_error)
        return false
    }
    
    if bytes_written != len(message) {
        fmt.printf("Error: partial write to '%v': wrote %v/%v bytes\n", address_and_port_from_socket(socket), bytes_written, len(message))
        return false
    }
    
    return true
}

receive :: proc (socket: net.TCP_Socket, buffer: [] u8) -> (int, bool) {
    read, receive_error := net.recv_tcp(socket, buffer[:])
    if receive_error != nil {
        fmt.printf("Error: failed to receive from '%v': %v\n", address_and_port_from_socket(socket), receive_error)
        return read, false
    }
    return read, true
}

dial_send_receive_and_close :: proc (host_and_port: string, message: string) {
    socket, dial_ok := dial(host_and_port)
    if !dial_ok do os.exit(1)
    fmt.printf("Calling '%v' with message:'%v'\n", host_and_port, message)
    
    if !send(socket, message) do os.exit(1)
    fmt.printf("Wrote %v bytes to %v\n", len(message), host_and_port)
    
    buffer: [1024] u8
    read, read_ok := receive(socket, buffer[:])
    if !read_ok do os.exit(1)
    
    fmt.printf("Received %v bytes from %v:\n%v\n", read, host_and_port, to_string(buffer[:read]))
    
    net.close(socket)
    fmt.printf("Disconnecting...\n")
}

address_and_port_from_socket :: proc (socket: net.TCP_Socket) -> string {
    endpoint, _ := net.bound_endpoint(socket)
    address_and_port := net.endpoint_to_string(endpoint, context.allocator)
    return address_and_port
}

////////////////////////////////////////////////

route_yourproblem :: proc (response: ^Response) {
    response.code = .Bad_Request
    response.body = `
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
}
route_myproblem :: proc (response: ^Response) {
    response.code = .Internal_Server_Error
    response.body = `
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
}

route_any :: proc  (response: ^Response) {
    response.code = .OK
    response.body = `
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

is_route :: proc (r: Request, wanted_route: string) -> bool {
    result, _ := is_route_and_rest(r, wanted_route)
    return result
}

// @todo(viktor): this assumes a route line '/endpoint' and does not handle nested like '/we/need/to/go/deeper'
is_route_and_rest :: proc (r: Request, wanted_route: string) -> (bool, string) {
    assert(r.done_upto >= .request_line)
    
    route := r.request_target
    before, found := chop_until(&route, '/')
    if !found {
        // @todo(viktor): error, invalid request_target?
    }
    
    first, has_more := chop_until(&route, '/')
    // @todo(viktor): return the rest behind the first route
    result := ends_with(wanted_route, first) // the slash was removed by the chop
    return result, route
}