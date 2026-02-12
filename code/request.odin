package main

import "core:fmt"
import "core:strings"
import "core:strconv"

Request :: struct {
    valid: bool,
    
    allocator: Allocator   "fmt:\"-\"",
    backing:   Byte_Buffer "fmt:\"-\"", // the request data is copied into here
    headers:   Headers,     // header keys are reallocated to ensure lowercase, values are views into the backing buffer
    
    // these strings are views into the backing buffer
    method:         string,
    request_target: string,
    http_version:   string,
    body:           string,
}

Headers :: struct {
    internal: map[string] string,
}

////////////////////////////////////////////////

request_init :: proc (result: ^Request, allocator: Allocator) {
    result.allocator = allocator
    result.headers = make_headers(result.allocator)
    result.backing = make_byte_buffer(make([] u8, 1024, result.allocator))
}

request_parse_from_socket :: proc (result: ^Request, reader: ^SocketReadContext, allocator: Allocator) {
    reader.buffer = make_byte_buffer(reader._backing[:])
    request_parse(result, reader, allocator, socket_read_until, socket_read_count, socket_read_done)
}

// @note(viktor): this is only here for testing
request_parse_from_string :: proc (data: string) -> Request{
    result: Request
    reader: StringReadContext
    reader.buffer = make_byte_buffer(to_bytes(data))
    reader.buffer.write_cursor = len(data)
    request_parse(&result, &reader, context.temp_allocator, string_read_until, string_read_count, string_read_done)
    return result
}

request_parse :: proc (request: ^Request, reader: ^$T, allocator: Allocator, $read_until: proc(^T, ^Byte_Buffer, string) -> bool, $read_count: proc (^T, ^Byte_Buffer, int) -> bool, $read_done: proc(^T) -> bool) {
    do_request_line, do_headers, do_body: bool
    
    request_init(request, allocator)
    assert(request.allocator != {}, "Request was not initialized")
    
    do_request_line = true
    
    // Requestline
    if do_request_line {
        if read_until(reader, &request.backing, "\r\n") {
            request_line := buffer_read_all_string(&request.backing)
            
            request.method         = chop_until_space(&request_line)
            request.request_target = chop_until_space(&request_line)
            request.http_version   = chop_until_space(&request_line)
            
            // @todo(viktor): validate request_target
            if is_valid_method(request) && is_valid_http_version(request) {
                do_headers = true
            }
        }
    }
    
    // Headers
    if do_headers {
        loop: for read_until(reader, &request.backing, "\r\n") {
            header_line := buffer_read_all_string(&request.backing)
            
            if header_line != "\r\n" {
                header_line = trim(header_line)
                
                key := chop_until(&header_line, ':')
                if is_valid_header_key(key) {
                    value := trim(header_line)
                    header_set(&request.headers, key, value, request.allocator)
                } else {
                    break loop
                }
            } else {
                do_body = true
                break loop
            }
        }
    }
    
    // Body
    if do_body {
        reported_content_length_string, key_ok := header_get_lower(&request.headers, "content-length")
        reported_content_length: int
        
        content_ok: bool
        actual_content: string
        if key_ok {
            parse_ok: bool
            reported_content_length, parse_ok = strconv.parse_int(reported_content_length_string)
        }
        
        read_ok := read_count(reader, &request.backing, reported_content_length)
        if read_ok && read_done(reader) {
            actual_content = buffer_read_all_string(&request.backing)
            content_ok = len(actual_content) == reported_content_length
        }
        
        if content_ok {
            request.body = actual_content
            request.valid = true
        }
    }
}

////////////////////////////////////////////////

make_headers :: proc (allocator: Allocator) -> Headers {
    result := Headers {
        make(map[string] string, allocator)
    }
    return result
}

// @todo(viktor): both set and get also check for a valid key?
header_set :: proc (headers: ^Headers, key, value: string, allocator: Allocator) {
    key_lower := strings.to_lower(key, allocator)
    header_set_lower(headers, key_lower, value)
}

header_get :: proc (headers: ^Headers, key: string, allocator: Allocator) -> (string, bool) #optional_ok {
    key_lower := strings.to_lower(key, allocator)
    result, ok := header_get_lower(headers, key_lower)
    return result, ok
}


// @todo(viktor): both set and get internal only, assert that its lower and valid
header_set_lower :: proc (headers: ^Headers, key_lower, value: string) {
    _, value_pointer, just_inserted, _ := map_entry(&headers.internal, key_lower)
    if !just_inserted {
        new_value, _ := strings.concatenate({value_pointer^, ", ", value}, context.allocator)
        value_pointer^ = new_value
    } else {
        value_pointer^ = value
    }
}

header_get_lower :: proc (headers: ^Headers, key_lower: string) -> (string, bool) #optional_ok {
    result, ok := headers.internal[key_lower]
    return result, ok
}

////////////////////////////////////////////////

is_valid_method :: proc (request: ^Request) -> bool {
    result := request.method == "GET" || request.method == "POST"
    return result
}

is_valid_http_version :: proc (request: ^Request) -> bool {
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