package main

import "core:strings"
import "core:fmt"

ResponceCode :: enum {
    OK = 200,
    Bad_Request = 400,
    Not_Found = 404,
    Internal_Server_Error = 500,
}

get_default_headers :: proc (headers: ^Headers, content_length: int) {
    header_set_lower(headers, "connection", "close")
    header_set_lower(headers, "content-type", "text/plain")
    header_set_lower(headers, "content-length", fmt.tprintf("%v", content_length))
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

write_headers :: proc (sb: ^strings.Builder, headers: ^Headers) {
    fmt.sbprintf(sb, "Content-Length: %v\r\n", header_get_lower(headers, "content-length"))
    fmt.sbprintf(sb, "Content-Type: %v\r\n",   header_get_lower(headers, "content-type"))
    fmt.sbprintf(sb, "Connection: %v\r\n",     header_get_lower(headers, "connection"))
}

write_body :: proc (sb: ^strings.Builder, body: string) {
    fmt.sbprintf(sb, "\r\n%v", body)
}