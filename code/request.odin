package main

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

////////////////////////////////////////////////

parse_from_socket :: proc (reader: ^SocketReadContext) -> HttpRequest {
    return parse(reader, socket_read_rn, socket_read_all)
}

parse_from_string :: proc (data: string) -> HttpRequest {
    reader := StringReadContext { data = data }
    return parse(&reader, string_read_rn, string_read_all)
}

parse :: proc (reader: ^$T, $read_rn, $read_all: proc (^T, ^[dynamic] u8) -> Read_Result) -> HttpRequest {
    result: HttpRequest
    result.headers = make([dynamic] Header, context.allocator)
    
    received := make([dynamic] u8, context.allocator)
    if read_rn(reader, &received) != .ShouldClose {
        request_line := to_string(received[:])
        read_cursor := len(request_line)
        
        result.method         = chop_until_space(&request_line)
        result.request_target = chop_until_space(&request_line)
        result.http_version   = chop_until_space(&request_line)
        
        // @todo(viktor): validate request_target
        if is_valid_method(result) && is_valid_http_version(result) {
            loop: for read_rn(reader, &received) != .ShouldClose {
                header_line := to_string(received[read_cursor:])
                read_cursor += len(header_line)
                
                if header_line != "\r\n" {
                    header: Header
                    header.key   = chop_until(&header_line, ':')
                    header.value = trim(header_line)
                    append(&result.headers, header)
                } else {
                    if read_all(reader, &received) != .ShouldClose{
                        result.body = to_string(received[read_cursor:])
                        result.valid = true
                    }
                    break loop
                }
            }
        }
    }
    
    return result
}

////////////////////////////////////////////////

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
