package client

import "core:strings"
import os "core:os/os2"

import code ".."

main :: proc () {
    once(3)
}

once :: proc (kind: int) {
    host_and_port := "localhost:42069"
    
    sb: strings.Builder
    message: string
    switch kind {
    case 0: message = code.write_request(&sb, "GET", "/", "Hello World")
    case 1: message = code.write_request(&sb, "GET", "/yourproblem", "w")
    case 2: message = code.write_request(&sb, "GET", "/myproblem")
    case 3: message = code.write_request(&sb, "GET", "localhost:402069/httpbin/stream/100")
    }
    
    if !code.dial_send_receive_and_close(host_and_port, message) do os.exit(1)
}
