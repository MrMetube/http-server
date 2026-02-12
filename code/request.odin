package main

import "core:fmt"
import "core:strings"
import "core:strconv"

Request :: struct {
    invalid: bool,
    
    allocator: Allocator   "fmt:\"-\"",
    buffer:    Byte_Buffer "fmt:\"-\"", // the request data is copied into here
    headers:   Headers,     // header keys are reallocated to ensure lowercase, values are views into the backing buffer
    
    // these strings are views into the backing buffer
    method:         string,
    request_target: string,
    http_version:   string,
    body:           string,
    
    done_upto: Request_Section,
}

Request_Section :: enum u8 { none, request_line, headers, body }

Headers :: struct {
    internal: map[string] string,
}

Response ::struct {
    code:    ResponceCode,
    headers: Headers,
    content: string,
}

////////////////////////////////////////////////

request_init :: proc (result: ^Request, allocator: Allocator) {
    result.allocator = allocator
    result.headers = make_headers(result.allocator)
    result.buffer = make_byte_buffer(make([] u8, 1024, result.allocator))
}

request_parse_from_socket :: proc (result: ^Request, upto: Request_Section, reader: ^SocketReadContext) {
    request_parse(result, upto, reader)
}

// @note(viktor): this is only here for testing
request_parse_from_string :: proc (data: string) -> Request{
    result: Request
    reader: StringReadContext
    reader.buffer = make_byte_buffer(to_bytes(data))
    reader.buffer.write_cursor = len(data)
    request_init(&result, context.temp_allocator)
    
    request_parse(&result, .request_line, &reader)
    request_parse(&result, .headers,      &reader)
    request_parse(&result, .body,         &reader)
    
    return result
}

request_parse :: proc (request: ^Request, upto: Request_Section, reader: ^$T) {
    assert(request.allocator != {}, "Request was not initialized")
    
    // Requestline
    if !request.invalid && request.done_upto < .request_line && .request_line <= upto {
        if read_until(reader, &request.buffer, "\r\n") {
            request_line := buffer_read_all_string(&request.buffer)
            
            request.method         = chop_until_space(&request_line)
            request.request_target = chop_until_space(&request_line)
            request.http_version   = chop_until_space(&request_line)
            
            // @todo(viktor): validate request_target
            if is_valid_method(request) && is_valid_http_version(request) {
                 request.done_upto = .request_line
            } else {
                request.invalid = true
            }
        } else {
            request.invalid = true
        }
    }
    
    // Headers
    if !request.invalid && request.done_upto < .headers && .headers <= upto {
        loop: for read_until(reader, &request.buffer, "\r\n") {
            header_line := buffer_read_all_string(&request.buffer)
            
            if header_line != "\r\n" {
                header_line = trim(header_line)
                
                key := chop_until(&header_line, ':')
                if is_valid_header_key(key) {
                    value := trim(header_line)
                    headers_set(&request.headers, key, value, request.allocator)
                } else {
                    request.invalid = true
                    break loop
                }
            } else {
                break loop
            }
        }
        
        request.done_upto = .headers
    }
    
    // Body
    if !request.invalid && request.done_upto < .body && .body <= upto {
        // @todo(viktor): helper header_get_int?
        reported_content_length_string, exists := headers_get_lower(&request.headers, "content-length")
        reported_content_length: int
        
        content_ok: bool
        actual_content: string
        if exists {
            parse_ok: bool
            reported_content_length, parse_ok = strconv.parse_int(reported_content_length_string)
        }
        
        if read_count(reader, &request.buffer, reported_content_length) && read_done(reader) {
            actual_content = buffer_read_all_string(&request.buffer)
            
            if reported_content_length == len(actual_content) {
                request.body = actual_content
            } else {
                request.invalid = true
            }
        } else {
            request.invalid = true
        }
        
        request.done_upto = .body
    }
    
    // @todo(viktor): trailers
}

////////////////////////////////////////////////

make_headers :: proc (allocator: Allocator) -> Headers {
    result := Headers {
        make(map[string] string, allocator)
    }
    return result
}

// @todo(viktor): both set and get also check for a valid key?
headers_set :: proc (headers: ^Headers, key, value: string, allocator: Allocator) {
    key_lower := strings.to_lower(key, allocator)
    headers_set_lower(headers, key_lower, value)
}
headers_get :: proc (headers: ^Headers, key: string, allocator: Allocator) -> (string, bool) #optional_ok {
    key_lower := strings.to_lower(key, allocator)
    result, ok := headers_get_lower(headers, key_lower)
    return result, ok
}

// @todo(viktor): both set and get internal only, assert that its lower and valid
headers_set_lower :: proc (headers: ^Headers, key_lower, value: string) {
    _, value_pointer, just_inserted, _ := map_entry(&headers.internal, key_lower)
    if !just_inserted {
        new_value, _ := strings.concatenate({value_pointer^, ", ", value}, context.allocator)
        value_pointer^ = new_value
    } else {
        value_pointer^ = value
    }
}
headers_unset_lower :: proc (headers: ^Headers, key_lower: string) {
    delete_key(&headers.internal, key_lower)
}
headers_get_lower :: proc (headers: ^Headers, key_lower: string) -> (string, bool) #optional_ok {
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
    r = request_parse_from_string("GET / HTTP/1.1\r\n\r\n"); assert(!r.invalid)
    
    r = request_parse_from_string("GET / HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n"); assert(!r.invalid)
    r = request_parse_from_string("POST /help/me/escape HTTP/1.0\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n"); assert(!r.invalid)
    r = request_parse_from_string("GET / HTTP/1.1\r\nHost: localhost:42069\r\nHost: localhost:6969\r\n\r\n"); assert(!r.invalid)
    r = request_parse_from_string("GET / HTTP/1.1\r\nhost: localhost:42069\r\nHOST: localhost:6969\r\n\r\n"); assert(!r.invalid)
    r = request_parse_from_string("GET / HTTP/1.1\r\nHost`: localhost:42069\r\n\r\n"); assert(!r.invalid)
    
    r = request_parse_from_string("GET / HTTP/1.1\r\nHost : localhost:42069\r\n\r\n"); assert(r.invalid)
    r = request_parse_from_string("GET / HTTP/1.1\r\nHost:"); assert(r.invalid)
    r = request_parse_from_string("GET / HTTP/1.1\r\n\r\nKey: Value"); assert(r.invalid)
    r = request_parse_from_string("GET / HTTP/1.1\r\nHost´: localhost:42069\r\n\r\n"); assert(r.invalid)
    r = request_parse_from_string("GET / HTTP/1.1\r\n     Host:               localhost:42069            \r\n\r\n"); assert(!r.invalid)
    
    r = request_parse_from_string("Invalid // HTTP/1.1\r\n\r\n"); assert(r.invalid)
    r = request_parse_from_string("get / HTTP/1.1\r\n\r\n"); assert(r.invalid)
    r = request_parse_from_string("GET / HTTP/add.0\r\n\r\n"); assert(r.invalid)
    r = request_parse_from_string("GET  /  HTTP/1.1\r\n\r\n\r\n"); assert(r.invalid)
    r = request_parse_from_string("/ GET HTTP/1.1\r\n\r\n"); assert(r.invalid)
    r = request_parse_from_string("GE"); assert(r.invalid)
    
    r = request_parse_from_string("POST /submit HTTP/1.1\r\n\r\n"); assert(!r.invalid)
    r = request_parse_from_string("POST /submit HTTP/1.1\r\n\r\nA stray body"); assert(r.invalid)
    r = request_parse_from_string("POST /submit HTTP/1.1\r\nContent-Length: 0\r\n\r\n"); assert(!r.invalid)
    r = request_parse_from_string("POST /submit HTTP/1.1\r\nContent-Length: 13\r\n\r\nhello world!\n"); assert(!r.invalid)
    r = request_parse_from_string("POST /submit HTTP/1.1\r\nContent-Length: 20\r\n\r\npartial content"); assert(r.invalid)
    
    
    fmt.println("All tests passed")
}