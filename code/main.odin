#+vet explicit-allocators
package main

import "core:fmt"
import os "core:os/os2"
import "core:net"

main :: proc () {
    host_and_port := "localhost:42069"
    
    endpoint, resolve_error := net.resolve_ip4(host_and_port)
    if resolve_error != nil {
        fmt.printf("Error: failed to resolve endpoint '%v': %v\n", host_and_port, resolve_error)
        os.exit(1)
    }
    
    server, listen_error := net.listen_tcp(endpoint)
    if listen_error != nil {
        fmt.printf("Error: failed to create and listen on '%v': %v\n", host_and_port, listen_error)
        os.exit(1)
    }
    defer net.close(server)
    
    fmt.printf("Start listening on %v\n", host_and_port)
    
    for {
        client, client_source, accept_error := net.accept_tcp(server)
        if accept_error != nil {
            fmt.printf("Error: failed to accept a client tcp on '%v': %v\n", host_and_port, accept_error)
            os.exit(1)
        }
        
        fmt.printf("Connection accepted by %v with source %v\n", client, client_source)
        
        reader: SocketReadContext
        reader.host_and_port = host_and_port
        reader.socket = client
        
        r: HttpRequest
        r = parse_from_socket(&reader)
        
        fmt.printf("------------------------------\nConnection closed with %v and source %v\n", client, client_source)
        
        r = parse_from_string("GET / HTTP/1.1\r\n\r\n")
        assert(r.valid)
        
        r = parse_from_string("GET / HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\nThis is a body\r\n")
        assert(r.valid)
        r = parse_from_string("POST /help/me/escape HTTP/1.0\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\nThis is a body\r\n")
        assert(r.valid)
        
        r = parse_from_string("Invalid // HTTP/1.1\r\n")
        assert(!r.valid)
        r = parse_from_string("get / HTTP/1.1\r\n")
        assert(!r.valid)
        r = parse_from_string("GET / HTTP/add.0\r\n")
        assert(!r.valid)
        r = parse_from_string("GET  /  HTTP/1.1\r\n\r\n")
        assert(!r.valid)
        r = parse_from_string("/ GET HTTP/1.1\r\n")
        assert(!r.valid)
        
        r = parse_from_string("GE")
        assert(!r.valid)
        
        fmt.println("All tests passed")
    }
}

////////////////////////////////////////////////

chop_until :: proc (data: ^string, until: u8) -> (string, bool) #optional_ok {
    ok: bool
    index: int
    for ; index <len(data); index += 1 {
        if data[index] == until {
            ok = true
            break
        }
    }
    
    result := data[:index]
    if index+1 < len(data) {
        data^ = data[index+1:]
    } else {
        data^ = ""
    }
    
    return result, ok
}

chop_until_space :: proc (data: ^string) -> (string, bool) #optional_ok {
    // @copypasta from chop_until
    ok: bool
    index: int
    for ; index <len(data); index += 1 {
        if is_space(data[index]) {
            ok = true
            break
        }
    }
    
    result := data[:index]
    if index+1 < len(data) {
        data^ = data[index+1:]
    } else {
        data^ = ""
    }
    
    return result, ok
}

////////////////////////////////////////////////

chop_until_rn :: proc (data: ^string) -> (string, bool) #optional_ok {
    result, ok := chop_until(data, '\r')
    if ok {
        data ^= data[1:] // also drop the \n
    }
    return result, ok
}

find_rn :: proc (data: string) -> bool {
    result: bool
    for index in 0..<len(data)-1 {
        if data[index] == '\r' && data[index+1] == '\n' {
            result = true
            break
        }
    }
    return result
}

////////////////////////////////////////////////

trim :: proc (data: string) -> string {
    result := data
    result = trim_left(result)
    result = trim_right(result)
    return result
}
trim_right :: proc (data: string) -> string {
    result := data
    for len(result) > 0 && is_space(result[len(result)-1]) do result = result[:len(result)-1]
    return result
}
trim_left :: proc (data: string) -> string {
    result := data
    for len(result) > 0 && is_space(result[0]) do result = result[1:]
    return result
}

////////////////////////////////////////////////

is_space :: proc (char: u8) -> bool {
    result: bool
    switch char {
    case ' ', '\t', '\n', '\r', '\v': result = true
    }
    return result
}

////////////////////////////////////////////////

to_string :: proc (data: [] u8) -> string {
    return transmute(string) data
}
to_bytes :: proc (data: string) -> [] u8 {
    return transmute([] u8) data
}

////////////////////////////////////////////////

SocketReadContext :: struct {
    host_and_port: string,
    socket: net.TCP_Socket,
    
    buf: [8] u8,
    index: int,
    read_amount: int,
    
    read_error: net.TCP_Recv_Error,
}

Read_Result :: enum { CanBeContinued, Done, ShouldClose }

////////////////////////////////////////////////

// @compress the copy loop is also similar and should be compressable. @speed that would also avoid appending each byte one by one
socket_read_line :: proc (reader: ^SocketReadContext, destination: ^[dynamic] u8) -> Read_Result {
    for {
        begin_socket_read(reader)
        
        read_done: bool
        copy: for reader.index < reader.read_amount {
            it := reader.buf[reader.index]
            reader.index += 1
            
            append(destination, it)
            if it == '\n' {
                read_done = true
                break copy
            }
        }
        
        continue_reading, read_result := end_socket_read(reader, read_done)
        if !continue_reading do return read_result
    }
}

socket_read_count :: proc (reader: ^SocketReadContext, destination: ^[dynamic] u8, count: int, cursor: ^int) -> Read_Result {
    assert(count <= len(reader.buf))
    for {
        begin_socket_read(reader)
        
        read_done: bool
        copy: for reader.index < reader.read_amount {
            it := reader.buf[reader.index]
            reader.index += 1
            cursor^ += 1
            
            append(destination, it)
            if cursor^ == count {
                read_done = true
                cursor^ = 0
                break copy
            }
        }
        
        continue_reading, read_result := end_socket_read(reader, read_done)
        if !continue_reading do return read_result
    }
}

socket_read_rn:: proc (reader: ^SocketReadContext, destination: ^[dynamic] u8) -> Read_Result {
    for {
        begin_socket_read(reader)
        
        read_done: bool
        copy: for reader.index < reader.read_amount {
            it := reader.buf[reader.index]
            reader.index += 1
            
            append(destination, it)
            if len(destination) > 1 && destination[len(destination)-2] == '\r' && destination[len(destination)-1] == '\n' {
                read_done = true
                break copy
            }
        }
        
        continue_reading, read_result := end_socket_read(reader, read_done)
        if !continue_reading do return read_result
    }
}

socket_read_all :: proc (reader: ^SocketReadContext, destination: ^[dynamic] u8) -> Read_Result {
    for {
        begin_socket_read(reader)
        
        append_elems(destination, ..reader.buf[reader.index:reader.read_amount])
        reader.index = reader.read_amount
        
        continue_reading, read_result := end_socket_read(reader, false)
        if !continue_reading do return read_result
    }
}

////////////////////////////////////////////////

begin_socket_read :: proc (reader: ^SocketReadContext) {
    if reader.index == reader.read_amount {
        reader.read_amount, reader.read_error = net.recv_tcp(reader.socket, reader.buf[:])
        reader.index = 0
    }
}

end_socket_read :: proc (reader: ^SocketReadContext, pause_reading: bool) -> (bool, Read_Result) {
    continue_reading: bool
    result: Read_Result
    if reader.read_amount == 0 || reader.read_error == .Connection_Closed {
        result = .Done
    } else if reader.read_error != nil {
        fmt.printf("ERROR: Could not read from socket '%v': %v\n", reader.host_and_port, reader.read_error)
        result = .ShouldClose
    } else if pause_reading {
        result = .CanBeContinued
    } else {
        continue_reading = true
    }
    
    return continue_reading, result
}

////////////////////////////////////////////////

StringReadContext :: struct {
    data: string,
    index: int,
}

string_read_rn:: proc (reader: ^StringReadContext, destination: ^[dynamic] u8) -> Read_Result {
    for {
        read_done: bool
        copy: for reader.index < len(reader.data) {
            it := reader.data[reader.index]
            reader.index += 1
            
            append(destination, it)
            if len(destination) > 1 && destination[len(destination)-2] == '\r' && destination[len(destination)-1] == '\n' {
                read_done = true
                break copy
            }
        }
        
        if reader.index == len(reader.data) do return .Done
        if read_done do return .CanBeContinued 
    }
}

string_read_all :: proc (reader: ^StringReadContext, destination: ^[dynamic] u8) -> Read_Result {
    left := reader.data[reader.index:]
    append_string(destination, left)
    reader.index = len(left)
    
    return .Done
}

////////////////////////////////////////////////
