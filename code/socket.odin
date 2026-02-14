package main

import "core:fmt"
import "core:net"
import "core:strings"

Socket :: struct #all_or_none {
    valid: bool,

    socket:   net.TCP_Socket,
    endpoint: net.Endpoint,
}

////////////////////////////////////////////////

dial :: proc (host_and_port: string) -> Socket {
    socket, connect_error := net.dial_tcp_from_hostname_and_port_string(host_and_port)
    
    endpoint, _ := net.bound_endpoint(socket) // @waste
    result := Socket {
        valid = true,
        
        socket = socket,
        endpoint = endpoint, 
    }
    
    if connect_error != nil {
        error_and_close(&result, "Error: failed to connect to '%v': %v\n", host_and_port, connect_error)
    }
    
    return result
}

accept :: proc (server: Socket) -> Socket {
    if !server.valid do return {}
    
    client, endpoint, accept_error := net.accept_tcp(server.socket)
    
    result := Socket {
        valid = true,
        
        socket   = client,
        endpoint = endpoint,
    }
    
    if accept_error != nil {
        error_and_close(&result, "Error: failed to accept a client tcp on '%v': %v\n", address_and_port_from_socket(server), accept_error)
    }
    
    return result
}

////////////////////////////////////////////////

listen :: proc (endpoint: net.Endpoint) -> Socket {
    server_socket, listen_error := net.listen_tcp(endpoint)
    
    result:= Socket {
        valid = true,
        
        socket   = server_socket,
        endpoint = endpoint,
    }
    
    if listen_error != nil {
        error_and_close(&result, "Error: failed to create and listen on '%v': %v\n", address_and_port_from_socket(result), listen_error)
    }
    
    return result
}

send :: proc (socket: ^Socket, message: string) -> bool {
    if !socket.valid do return false
    
    bytes_written, write_error := net.send_tcp(socket.socket, to_bytes(message))
    if write_error != nil {
        error_and_close(socket, "Error: failed to write to '%v': %v\n", address_and_port_from_socket(socket^), write_error)
    } else if bytes_written != len(message) {
        error_and_close(socket, "Error: partial write to '%v': wrote %v/%v bytes\n", address_and_port_from_socket(socket^), bytes_written, len(message))
    }
    
    return socket.valid
}

receive :: proc (socket: ^Socket, buffer: [] u8) -> (int, bool) {
    if !socket.valid do return 0, false
    
    read, receive_error := net.recv_tcp(socket.socket, buffer[:])
    if receive_error != nil {
        error_and_close(socket, "Error: failed to receive from '%v': %v\n", address_and_port_from_socket(socket^), receive_error)
    }
    
    return read, socket.valid
}

close :: proc (socket: ^Socket) {
    net.close(socket.socket)
    socket.valid = false
}

////////////////////////////////////////////////
// Helpers

error_and_close :: proc (socket: ^Socket, format: string, args: ..any) {
    fmt.printf(format, ..args)
    close(socket)
}

send_and_reset :: proc (socket: ^Socket, sb: ^strings.Builder) -> bool {
    result := send(socket, strings.to_string(sb^))
    strings.builder_reset(sb)
    return result
}

dial_send_receive_and_close :: proc (host_and_port: string, message: string) -> bool {
    socket := dial(host_and_port)
    if !socket.valid do return false
    
    fmt.printf("Calling '%v' with message:'%v'\n", host_and_port, message)
    
    if !send(&socket, message) do return false
    fmt.printf("Wrote %v bytes to %v\n", len(message), host_and_port)
    
    buffer: [1024] u8
    read, read_ok := receive(&socket, buffer[:])
    if !read_ok do return false
    
    fmt.printf("Received %v bytes from %v:\n%v\n", read, host_and_port, to_string(buffer[:read]))
    
    fmt.printf("Disconnecting...\n")
    close(&socket)
    
    return true
}

address_and_port_from_socket :: proc (socket: Socket) -> string {
    address_and_port := net.endpoint_to_string(socket.endpoint, context.allocator)
    return address_and_port
}