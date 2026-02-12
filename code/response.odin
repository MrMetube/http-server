package main

import "core:strings"
import "core:fmt"

ResponceCode :: enum {
    OK = 200,
    Bad_Request = 400,
    Not_Found = 404,
    Internal_Server_Error = 500,
}

Default_Headers :: struct {
    content_length: int,
    connection: string,
    content_type: string,
}

get_default_headers :: proc (content_length: int) -> Default_Headers {
    result: Default_Headers
    result.connection = "close"
    result.content_type = "text/plain"
    result.content_length = content_length
    return result
}

write_response_line :: proc (sb: ^strings.Builder, code: ResponceCode) {
    reason_phrase: string
    switch code {
    case .OK:                    reason_phrase = "OK"
    case .Bad_Request:           reason_phrase = "Bad Request"
    case .Not_Found:             reason_phrase = "Not Found"
    case .Internal_Server_Error: reason_phrase = "Internal Server Error"
    }
    
    fmt.sbprintf(sb, "HTTP/1.1 %v %v\r\n", cast(int) code, reason_phrase)
}

write_headers :: proc (sb: ^strings.Builder, default: Default_Headers) {
    fmt.sbprintf(sb, "Content-Length: %v\r\n", default.content_length)
    fmt.sbprintf(sb, "Content-Type: %v\r\n", default.content_type)
    fmt.sbprintf(sb, "Connection: %v\r\n", default.connection)
}

write_body :: proc (sb: ^strings.Builder, body: string) {
    fmt.sbprintf(sb, "\r\n%v", body)
}