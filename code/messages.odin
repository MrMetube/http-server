package main

import "core:fmt"
import "core:strings"
import "core:strconv"

Request :: struct {
    invalid:   bool,
    done_upto: Section,
    
    allocator: Allocator   "fmt:\"-\"",
    buffer:    Byte_Buffer "fmt:\"-\"", // the request data is copied into here
    headers:   Headers,     // header keys are reallocated to ensure lowercase, values are views into the backing buffer
    
    // these strings are views into the backing buffer
    method:         string,
    request_target: string,
    http_version:   string,
    body:           string,
}

Section :: enum u8 { 
    none, 
    request_line, // @naming is also used by response like the response_line
    headers, 
    body,
}

Headers :: struct {
    internal: map[string] string,
}

Response :: struct {
    invalid:   bool,
    done_upto: Section,
    
    allocator: Allocator   "fmt:\"-\"",
    buffer:    Byte_Buffer "fmt:\"-\"", // the request data is copied into here
    headers:   Headers,     // header keys are reallocated to ensure lowercase, values are views into the backing buffer
    
    // these strings are views into the backing buffer
    code: ResponseCode,
    body: string,
}

ResponseCode :: enum {
    None                  =   0,
    OK                    = 200,
    Bad_Request           = 400,
    Not_Found             = 404,
    Internal_Server_Error = 500,
}

////////////////////////////////////////////////

make_response :: proc (allocator: Allocator) -> Response {
    result: Response
    result.allocator = allocator
    result.headers   = make_headers(result.allocator)
    result.buffer    = make_byte_buffer(make([] u8, 4 * Kilobyte, result.allocator))
    return result
}

// @todo(viktor): separate RequestParser from Request
// @todo(viktor): The buffer size is hard coded, actually handle the case where the message exceeds the buffer
make_request :: proc (allocator: Allocator) -> Request {
    result: Request
    result.allocator = allocator
    result.headers   = make_headers(result.allocator)
    result.buffer    = make_byte_buffer(make([] u8, 4 * Kilobyte, result.allocator))
    
    return result
}

////////////////////////////////////////////////

add_default_headers :: proc (headers: ^Headers, content_length: int) {
    headers_set_lower(headers, "connection", "close")
    headers_set_lower(headers, "content-type", "text/plain")
    
    headers_set_lower(headers, "content-length", fmt.aprintf("%v", content_length, allocator = headers.internal.allocator))
}

add_default_headers_chunked :: proc (headers: ^Headers) {
    headers_set_lower(headers, "connection", "close")
    headers_set_lower(headers, "content-type", "text/plain")
    
    headers_set_lower(headers, "transfer-encoding", "chunked")
}

write_response_line :: proc (sb: ^strings.Builder, code: ResponseCode) {
    reason_phrase: string
    switch code {
    case .None: unreachable()
    
    case .OK:                    reason_phrase = "OK"
    case .Bad_Request:           reason_phrase = "Bad Request"
    case .Not_Found:             reason_phrase = "Not Found"
    case .Internal_Server_Error: reason_phrase = "Internal Server Error"
    }
    
    fmt.sbprintf(sb, "HTTP/1.1 %v %v\r\n", cast(int) code, reason_phrase)
}

write_headers_key :: proc (sb: ^strings.Builder, key: string) {
    fmt.sbprintf(sb, "%v: ", key)
}
write_headers_value :: proc (sb: ^strings.Builder, value: string) {
    fmt.sbprintf(sb, "%v\r\n", value)
}
write_headers :: proc (sb: ^strings.Builder, headers: ^Headers) {
    for key, value in headers.internal {
        write_headers_key(sb, key)
        write_headers_value(sb, value)
    }
    fmt.sbprintf(sb, "\r\n")
}

write_body :: proc (sb: ^strings.Builder, body: string) {
    fmt.sbprintf(sb, "%v", body)
}

////////////////////////////////////////////////

request_parse_from_socket :: proc (result: ^Request, reader: ^SocketReadContext, upto: Section) {
    request_parse(result, reader, upto)
}

response_parse_from_socket :: proc (result: ^Response, reader: ^SocketReadContext, upto: Section) {
    response_parse(result, reader, upto)
}

// @note(viktor): this is only here for testing
request_parse_from_string :: proc (data: string) -> Request {
    reader: StringReadContext
    reader.buffer = make_byte_buffer(to_bytes(data))
    reader.buffer.write_cursor = len(data)
    result := make_request(context.temp_allocator)
    
    request_parse(&result, &reader, .request_line)
    request_parse(&result, &reader, .headers)
    request_parse(&result, &reader, .body)
    
    return result
}

request_parse :: proc (request: ^Request, reader: ^$T, upto: Section) {
    assert(request.allocator != {}, "Request was not initialized")
    
    // Requestline
    if !request.invalid && request.done_upto < .request_line && .request_line <= upto {
        if read_until(&request.buffer, reader, "\r\n") {
            request_line := buffer_read_all_string(&request.buffer)
            
            request.method         = chop_until_space(&request_line)
            request.request_target = chop_until_space(&request_line)
            request.http_version   = chop_until_space(&request_line)
            
            if is_valid_method(request) && is_valid_http_version(request.http_version) {
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
        if !parse_headers(&request.buffer, reader, &request.headers) {
            request.invalid = true
        }
        
        request.done_upto = .headers
    }
    
    // Body
    if !request.invalid && request.done_upto < .body && .body <= upto {
        reported_content_length := headers_get_int(&request.headers, "content-length") or_else 0
        
        if read_count(&request.buffer, reader, reported_content_length) && read_done(reader) {
            actual_content := buffer_read_all_string(&request.buffer)
            
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

response_parse :: proc (response: ^Response, reader: ^$T, upto: Section) {
    assert(response.allocator != {}, "Response was not initialized")
    
    // Requestline
    if !response.invalid && response.done_upto < .request_line && .request_line <= upto {
        if read_until(&response.buffer, reader, "\r\n") {
            request_line := buffer_read_all_string(&response.buffer)
            
            http_version := chop_until_space(&request_line) // @todo(viktor): store this maybe?
            code_string  := chop_until_space(&request_line)
            reason       := chop_until_space(&request_line)
            
            code, parse_ok := strconv.parse_int(code_string)
            
            if is_valid_response_code(code) && is_valid_http_version(http_version) {
                 response.done_upto = .request_line
            } else {
                response.invalid = true
            }
        } else {
            response.invalid = true
        }
    }
    
    // Headers
    if !response.invalid && response.done_upto < .headers && .headers <= upto {
        if !parse_headers(&response.buffer, reader, &response.headers) {
            response.invalid = true
        }
        
        response.done_upto = .headers
    }
    
    // Body
    if !response.invalid && response.done_upto < .body && .body <= upto {
        reported_content_length := headers_get_int(&response.headers, "content-length") or_else 0
        
        if read_count(&response.buffer, reader, reported_content_length) && read_done(reader) {
            actual_content := buffer_read_all_string(&response.buffer)
            
            if reported_content_length == len(actual_content) {
                response.body = actual_content
            } else {
                response.invalid = true
            }
        } else {
            response.invalid = true
        }
        
        response.done_upto = .body
    }
    
    // @todo(viktor): trailers
}

////////////////////////////////////////////////

parse_headers :: proc (buffer: ^Byte_Buffer, reader: ^$T, headers: ^Headers) -> bool {
    ok := true
    loop: for read_until(buffer, reader, "\r\n") {
        header_line := buffer_read_all_string(buffer)
        
        if header_line != "\r\n" {
            header_line = trim(header_line)
            
            key := chop_until(&header_line, ':')
            if is_valid_header_key(key) {
                value := trim(header_line)
                headers_set(headers, key, value)
            } else {
                ok = false
                break loop
            }
        } else {
            break loop
        }
    }
    
    return ok
}

////////////////////////////////////////////////
// @todo(viktor): should regular fields like content-length always be stored as int and easily accessed? or does that not matter, because its too rare?
make_headers :: proc (allocator: Allocator) -> Headers {
    result := Headers {
        make(map[string] string, allocator)
    }
    return result
}

// @todo(viktor): both set and get also check for a valid key?
headers_set :: proc (headers: ^Headers, key, value: string, replace := false) {
    key_lower := strings.to_lower(key, headers.internal.allocator)
    headers_set_lower(headers, key_lower, value, replace = replace)
}
headers_get :: proc (headers: ^Headers, key: string) -> (string, bool) #optional_ok {
    key_lower := strings.to_lower(key, headers.internal.allocator)
    result, ok := headers_get_lower(headers, key_lower)
    return result, ok
}

// @todo(viktor): both set and get internal only, assert that its lower and valid
headers_set_lower :: proc (headers: ^Headers, key_lower, value: string, replace := false) {
    _, value_pointer, just_inserted, _ := map_entry(&headers.internal, key_lower)
    if !just_inserted {
        new_value: string
        if replace {
            new_value = value
        } else {
            new_value, _ = strings.concatenate({value_pointer^, ", ", value}, context.allocator)
        }
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

headers_get_int :: proc (headers: ^Headers, key: string) -> (int, bool) #optional_ok {
    value, ok := headers_get(headers, key)
    if !ok do return 0, ok
    
    result: int
    result, ok = strconv.parse_int(value)
    return result, ok
}

////////////////////////////////////////////////

is_valid_method :: proc (request: ^Request) -> bool {
    result := request.method == "GET" || request.method == "POST"
    return result
}

is_valid_response_code :: proc (code: int) -> bool {
    // @todo(viktor): implement this
    return true
}

is_valid_http_version :: proc (http_version: string) -> bool {
    version := http_version
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
    fmt.println("Start testing")
    
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