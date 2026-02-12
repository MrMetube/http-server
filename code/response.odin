#+vet explicit-allocators
package main

import "core:strings"
import "core:fmt"

ResponceCode :: enum {
    None = 0,
    OK = 200,
    Bad_Request = 400,
    Not_Found = 404,
    Internal_Server_Error = 500,
}

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

write_response_line :: proc (sb: ^strings.Builder, code: ResponceCode) {
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

write_headers :: proc (sb: ^strings.Builder, headers: ^Headers) {
    for key, value in headers.internal {
        fmt.sbprintf(sb, "%v: %v\r\n", key, value)
    }
}

write_body :: proc (sb: ^strings.Builder, body: string) {
    fmt.sbprintf(sb, "\r\n%v", body)
}