package main

import "core:strings"

HttpRequest :: struct {
    valid: bool,
    
    method:         string,
    request_target: string,
    http_version:   string,
    
    headers: map[string] string,
    body: string,
}

////////////////////////////////////////////////

parse_from_socket :: proc (reader: ^SocketReadContext) -> HttpRequest {
    reader.buffer = make_byte_buffer(reader._backing[:])
    return parse(reader, socket_read_until, socket_read_all)
}

parse_from_string :: proc (data: string) -> HttpRequest {
    reader: StringReadContext
    reader.buffer = make_byte_buffer(to_bytes(data))
    reader.buffer.write_cursor = len(data)
    return parse(&reader, string_read_until, string_read_all)
}

parse :: proc (reader: ^$T, $read_until: proc(^T, ^Byte_Buffer, string) -> Read_Result, $read_all: proc (^T, ^Byte_Buffer) -> Read_Result) -> HttpRequest {
    result: HttpRequest
    result.headers = make(map[string] string, context.allocator)
    
    buffer:= make_byte_buffer(make([] u8, 1024, context.allocator))
    
    if read_until(reader, &buffer, "\r\n") != .ShouldClose {
        request_line := buffer_read_all_string(&buffer)
        
        result.method         = chop_until_space(&request_line)
        result.request_target = chop_until_space(&request_line)
        result.http_version   = chop_until_space(&request_line)
        
        // @todo(viktor): validate request_target
        if is_valid_method(result) && is_valid_http_version(result) {
            loop: for read_until(reader, &buffer, "\r\n") != .ShouldClose {
                header_line := buffer_read_all_string(&buffer)
                
                if header_line != "\r\n" {
                    header_line = trim(header_line)
                    
                    key := chop_until(&header_line, ':')
                    if is_valid_header_key(key) {
                        value := trim(header_line)
                        header_set(&result.headers, key, value, context.allocator)
                    } else {
                        break loop
                    }
                } else {
                    if read_all(reader, &buffer) != .ShouldClose{
                        result.body = buffer_read_all_string(&buffer)
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

header_set :: proc (headers: ^map[string] string, key, value: string, allocator: Allocator) {
    // @todo(viktor): also check for a valid key?
    key_lower := strings.to_lower(key, allocator)
    _, value_pointer, just_inserted, _ := map_entry(headers, key_lower)
    if !just_inserted {
        new_value, _ := strings.concatenate({value_pointer^, ", ", value}, context.allocator)
        value_pointer^ = new_value
    } else {
        value_pointer^ = value
    }
}

header_get :: proc (headers: ^map[string] string, key: string, allocator: Allocator) -> (string, bool) #optional_ok {
    key_lower := strings.to_lower(key, allocator)
    result, ok := headers[key_lower]
    return result, ok
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

is_valid_header_key :: proc (header_key: string)  -> bool {
    valid_header_characters := [max(u8)] bool {
        '!'  = true,
        '#'  = true,
        '$'  = true,
        '%'  = true,
        '&'  = true,
        '\'' = true,
        '*'  = true,
        '+'  = true,
        '-'  = true,
        '.'  = true,
        '^'  = true,
        '_'  = true,
        '`'  = true,
        '|'  = true,
        '~'  = true,
        
         0  ..=  9  = true,
        'a' ..= 'z' = true,
        'A' ..= 'Z' = true,
    }
    
    for r in header_key {
        if !valid_header_characters[r] {
            return false
        }
    }
    
    if len(header_key) != 0 {
        return true
    } else {
        return false
    }
}