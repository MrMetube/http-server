package main

import "core:fmt"
import "core:strings"
import "core:strconv"

Request :: struct {
    valid: bool,
    
    method:         string,
    request_target: string,
    http_version:   string,
    
    headers: Headers,
    body: string,
}

Headers :: map[string] string
////////////////////////////////////////////////

request_parse_from_socket :: proc (reader: ^SocketReadContext) -> Request {
    reader.buffer = make_byte_buffer(reader._backing[:])
    return request_parse(reader, socket_read_until, socket_read_count, socket_read_done)
}

request_parse_from_string :: proc (data: string) -> Request {
    reader: StringReadContext
    reader.buffer = make_byte_buffer(to_bytes(data))
    reader.buffer.write_cursor = len(data)
    return request_parse(&reader, string_read_until, string_read_count, string_read_done)
}

request_parse :: proc (reader: ^$T, $read_until: proc(^T, ^Byte_Buffer, string) -> Read_Result, $read_count: proc (^T, ^Byte_Buffer, int) -> Read_Result, $read_done: proc(^T) -> bool) -> Request {
    result: Request
    result.headers = make(Headers, context.allocator)
    
    buffer:= make_byte_buffer(make([] u8, 1024, context.allocator))
    
    if read_until(reader, &buffer, "\r\n") != .ShouldClose {
        request_line := buffer_read_all_string(&buffer)
        
        result.method         = chop_until_space(&request_line)
        result.request_target = chop_until_space(&request_line)
        result.http_version   = chop_until_space(&request_line)
        
        // @todo(viktor): validate request_target
        if is_valid_method(result) && is_valid_http_version(result) {
            do_body: bool
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
                    do_body = true
                    break loop
                }
            }
            
            if do_body {
                
                reported_content_length_string, key_ok := header_get_lower(&result.headers, "content-length")
                reported_content_length: int
                
                content_ok: bool
                actual_content: string
                if key_ok {
                    parse_ok: bool
                    reported_content_length, parse_ok = strconv.parse_int(reported_content_length_string)
                }
                
                read_result := read_count(reader, &buffer, reported_content_length)
                if read_done(reader) {
                    actual_content = buffer_read_all_string(&buffer)
                    content_ok = len(actual_content) == reported_content_length
                }
                
                if content_ok {
                    result.body = actual_content
                    result.valid = true
                }
            }
        }
    }
    
    return result
}

////////////////////////////////////////////////

header_set :: proc (headers: ^Headers, key, value: string, allocator: Allocator) {
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

header_get :: proc (headers: ^Headers, key: string, allocator: Allocator) -> (string, bool) #optional_ok {
    key_lower := strings.to_lower(key, allocator)
    result, ok := header_get_lower(headers, key_lower)
    return result, ok
}
header_get_lower :: proc (headers: ^Headers, key_lower: string) -> (string, bool) #optional_ok {
    // @todo(viktor): internal only, assert that its lower
    result, ok := headers[key_lower]
    return result, ok
}

////////////////////////////////////////////////

is_valid_method :: proc (request: Request) -> bool {
    result := request.method == "GET" || request.method == "POST"
    return result
}

is_valid_http_version :: proc (request: Request) -> bool {
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

test_request_parsing :: proc () {
    r: Request
    r = request_parse_from_string("GET / HTTP/1.1\r\n\r\n"); assert(r.valid)
    
    r = request_parse_from_string("GET / HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n"); assert(r.valid)
    r = request_parse_from_string("POST /help/me/escape HTTP/1.0\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n"); assert(r.valid)
    r = request_parse_from_string("GET / HTTP/1.1\r\nHost: localhost:42069\r\nHost: localhost:6969\r\n\r\n"); assert(r.valid)
    r = request_parse_from_string("GET / HTTP/1.1\r\nhost: localhost:42069\r\nHOST: localhost:6969\r\n\r\n"); assert(r.valid)
    r = request_parse_from_string("GET / HTTP/1.1\r\nHost`: localhost:42069\r\n\r\n"); assert(r.valid)
    
    r = request_parse_from_string("GET / HTTP/1.1\r\nHost : localhost:42069\r\n\r\n"); assert(!r.valid)
    r = request_parse_from_string("GET / HTTP/1.1\r\nHost:"); assert(!r.valid)
    r = request_parse_from_string("GET / HTTP/1.1\r\n\r\nKey: Value"); assert(!r.valid)
    r = request_parse_from_string("GET / HTTP/1.1\r\nHost´: localhost:42069\r\n\r\n"); assert(!r.valid)
    r = request_parse_from_string("GET / HTTP/1.1\r\n     Host:               localhost:42069            \r\n\r\n"); assert(r.valid)
    
    r = request_parse_from_string("Invalid // HTTP/1.1\r\n\r\n"); assert(!r.valid)
    r = request_parse_from_string("get / HTTP/1.1\r\n\r\n"); assert(!r.valid)
    r = request_parse_from_string("GET / HTTP/add.0\r\n\r\n"); assert(!r.valid)
    r = request_parse_from_string("GET  /  HTTP/1.1\r\n\r\n\r\n"); assert(!r.valid)
    r = request_parse_from_string("/ GET HTTP/1.1\r\n\r\n"); assert(!r.valid)
    r = request_parse_from_string("GE"); assert(!r.valid)
    
    r = request_parse_from_string("POST /submit HTTP/1.1\r\n\r\n"); assert(r.valid)
    r = request_parse_from_string("POST /submit HTTP/1.1\r\n\r\nA stray body"); assert(!r.valid)
    r = request_parse_from_string("POST /submit HTTP/1.1\r\nContent-Length: 0\r\n\r\n"); assert(r.valid)
    r = request_parse_from_string("POST /submit HTTP/1.1\r\nContent-Length: 13\r\n\r\nhello world!\n"); assert(r.valid)
    r = request_parse_from_string("POST /submit HTTP/1.1\r\nContent-Length: 20\r\n\r\npartial content"); assert(!r.valid)
    
    
    fmt.println("All tests passed")
}