package updsender

import "core:fmt"
import os "core:os/os2"
import "core:net"

main :: proc () {
    host_and_port := "localhost:42069"

    endpoint, resolve_error := net.resolve_ip4(host_and_port)
    if resolve_error != nil {
        fmt.printf("Error: failed to resolve endpoint '%v': %v\n", host_and_port, resolve_error)
        os.exit(1)
    }
    
    {
        _socket, create_error := net.create_socket(.IP4, .UDP)
        socket := _socket.(net.UDP_Socket)
        if create_error != nil {
            fmt.printf("Error: failed to create socket: %v\n", create_error)
            os.exit(1)
        }
        defer net.close(socket)
        
        for {
            file_path := "./messages.txt"
    
            file, open_error := os.open(file_path)
            if open_error != nil {
                fmt.printf("ERROR: Could not open file '%v': %v\n", file_path, os.error_string(open_error))
                os.exit(1)
            }
            defer os.close(file)
            
            reader: FileReadContext
            reader.file_path = "Command line"
            reader.file = os.stdin
            
            for {
                line, done, read_error := file_read_line(&reader)
                
                if read_error != nil do os.exit(1)
                if done do break
                
                if len(line) == 0 do break
                
                bytes_written, write_error := net.send_udp(socket, transmute([] u8) line, endpoint)
                if write_error != nil {
                    fmt.printf("Error: failed to write to '%v': %v\n", host_and_port, write_error)
                    os.exit(1)
                }
                
                if bytes_written != len(line) {
                    fmt.printf("Error: partial write to '%v': wrote %v/%v bytes\n", host_and_port, bytes_written, len(line))
                    os.exit(1)
                }
                fmt.printf("Wrote %v bytes to %v\n", bytes_written, host_and_port)
            }
        }
    }
    
    fmt.printf("Disconnecting...\n")
}


file_read_test :: proc () {
    file_path := "./messages.txt"
    
    file, open_error := os.open(file_path)
    if open_error != nil {
        fmt.printf("ERROR: Could not open file '%v': %v\n", file_path, os.error_string(open_error))
        os.exit(1)
    }
    defer os.close(file)
    
    reader: FileReadContext
    reader.file_path = file_path
    reader.file = file
    
    for {
        line, done, read_error := file_read_line(&reader)
        
        if read_error != nil do os.exit(1)
        if done do break
        
        fmt.printf("read: %v", line)
    }
}

FileReadContext :: struct {
    file_path: string,
    file: ^os.File,
    buf: [8] u8,
    line: [dynamic] u8,
    
    index: int,
    read_amount: int,
}

file_read_line :: proc (reader: ^FileReadContext) -> (string, bool, os.Error) {
    for {
        if reader.index == reader.read_amount {
            read_error: os.Error
            reader.read_amount, read_error = os.read(reader.file, reader.buf[:])
                
            if read_error == .EOF {
                return "", true, read_error
            } else if read_error != nil {
                fmt.printf("ERROR: Could not read from file '%v': %v\n", reader.file_path, os.error_string(read_error))
                return "", true, read_error
            }
            reader.index = 0
        }
        
        for ; reader.index < reader.read_amount; reader.index += 1 {
            append(&reader.line, reader.buf[reader.index])
            if reader.buf[reader.index] == '\n' {
                result := transmute(string) reader.line[:]
                reader.index += 1
                clear(&reader.line)
                return result, false, nil
            }
        }
    }
}