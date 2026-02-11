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
        
        request_data: [dynamic] u8
        for {
            line, done, read_error := socket_read_line(&reader)
            
            append_string(&request_data, line)
            
            if read_error != nil do break
            if done do break
        }
        
        parse_request(to_string(request_data[:]))
        
        fmt.printf("\n------------------------------\nConnection closed with %v and source %v\n", client, client_source)
        reader_reset(&reader)
        
        r: HttpRequest
        r = parse_request("GET / HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\nThis is a body\r\n")
        assert(r.valid)
        r = parse_request("POST /help/me/escape HTTP/1.0\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\nThis is a body\r\n")
        assert(r.valid)
        
        r = parse_request("Invalid // HTTP/1.1\r\n")
        assert(!r.valid)
        r = parse_request("get / HTTP/1.1\r\n")
        assert(!r.valid)
        
        r = parse_request("GET / HTTP/add.0\r\n")
        assert(!r.valid)
        
        r = parse_request("/ GET HTTP/1.1\r\n")
        assert(!r.valid)
        
        r = parse_request("GE")
        assert(!r.valid)
        
        fmt.println("All tests passed")
    }
}

////////////////////////////////////////////////
HttpRequest :: struct {
    valid: bool,
    
    method:         string,
    request_target: string,
    http_version:   string,
    
    headers: [dynamic] Header,
    body: string,
}

Header :: struct {
    key:   string,
    value: string,
}

parse_request :: proc (data: string) -> HttpRequest {
    result: HttpRequest
    result.headers = make([dynamic] Header)
    result.valid = true
    
    data := data
    {
        request_line := chop_until_rn(&data)
        
        // @todo(viktor): technically multiple spaces should be an invalid request
        result.method         = trim(chop_until_space(&request_line))
        result.request_target = trim(chop_until_space(&request_line))
        result.http_version   = trim(chop_until_space(&request_line))
        
        result.valid &&= is_valid_method(result)
        // @todo(viktor): validate request_target
        result.valid &&= is_valid_http_version(result)
    }
    
    for {
        header := chop_until_rn(&data)
        if header == "" do break
        
        key := chop_until(&header, ':')
        value := trim(header)
        append(&result.headers, Header{ key, value })
    }
    
    result.body = data
    
    return result
}

is_valid_method :: proc (request: HttpRequest) -> bool {
    result := request.method == "GET" || request.method == "POST"
    return result
}

is_valid_http_version :: proc (request: HttpRequest) -> bool {
    version := request.http_version
    http := chop_until(&version, '/')
    
    result: bool
    if http == "HTTP" {
        major := chop_until(&version, '.')
        minor := version
        if major == "1" {
            if minor == "0" || minor == "1" {
                result = true
            }
        }
    }
    
    return result
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
    line: [dynamic] u8,
    
    index: int,
    read_amount: int,
}

reader_reset :: proc (reader: ^SocketReadContext) {
    clear(&reader.line)
    reader^ = { line = reader.line }
}

socket_read_line :: proc (reader: ^SocketReadContext) -> (string, bool, net.TCP_Recv_Error) {
    for {
        read_error: net.TCP_Recv_Error
        if reader.index == reader.read_amount {
            reader.read_amount, read_error = net.recv_tcp(reader.socket, reader.buf[:])
            reader.index = 0
        }
        
        result: string
        copy: for ; reader.index < reader.read_amount; reader.index += 1 {
            append(&reader.line, reader.buf[reader.index])
            if reader.buf[reader.index] == '\n' {
                result = transmute(string) reader.line[:]
                reader.index += 1
                clear(&reader.line)
                break copy
            }
        }
        
        if read_error == .Connection_Closed || reader.read_amount == 0 {
            result = transmute(string) reader.line[:]
            return result, true, read_error
        } else if read_error != nil {
            fmt.printf("ERROR: Could not read from socket '%v': %v\n", reader.host_and_port, read_error)
            result = transmute(string) reader.line[:]
            return result, true, read_error
        }
        
        if result != "" {
            return result, false, nil
        }
    }
}

////////////////////////////////////////////////
