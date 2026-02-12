package client

import "core:fmt"
import os "core:os/os2"
import "core:net"

main :: proc () {
    once(0)
    once(1)
    once(2)
}

once :: proc (kind: int) {
    host_and_port := "localhost:42069"

    endpoint, resolve_error := net.resolve_ip4(host_and_port)
    if resolve_error != nil {
        fmt.printf("Error: failed to resolve endpoint '%v': %v\n", host_and_port, resolve_error)
        os.exit(1)
    }
    
    {
        socket, connect_error := net.dial_tcp(endpoint)
        if connect_error != nil {
            fmt.printf("Error: failed to connect to '%v': %v\n", host_and_port, connect_error)
            os.exit(1)
        }
        
        defer net.close(socket)
        
        message: string
        switch kind {
        case 0: message = "GET / HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nContent-Length: 1\r\n\r\nw"
        case 1: message = "GET /yourproblem HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nContent-Length: 1\r\n\r\nw"
        case 2: message = "GET /myproblem HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nContent-Length: 1\r\n\r\nw"
        }
        send_message(socket, host_and_port, message)
        
        buffer: [1024] u8
        read, receive_error := net.recv_tcp(socket, buffer[:])
        if connect_error != nil {
            fmt.printf("Error: failed to receive from '%v': %v\n", host_and_port, receive_error)
            os.exit(1)
        }
        
        fmt.printf("Received %v bytes from %v:\n%v\n", read, host_and_port, transmute(string) buffer[:read])
    }
    
    fmt.printf("Disconnecting...\n")
}

send_message :: proc (socket: $T, host_and_port, message: string) {
    bytes_written, write_error := net.send_tcp(socket, transmute([] u8) message)
    if write_error != nil {
        fmt.printf("Error: failed to write to '%v': %v\n", host_and_port, write_error)
        os.exit(1)
    }
    
    if bytes_written != len(message) {
        fmt.printf("Error: partial write to '%v': wrote %v/%v bytes\n", host_and_port, bytes_written, len(message))
        os.exit(1)
    }
    fmt.printf("Wrote %v bytes to %v\n", bytes_written, host_and_port)
}