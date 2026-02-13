package main

import "core:fmt"
import "core:net"

SocketReadContext :: struct  {
    buffer: Byte_Buffer,
    socket: net.TCP_Socket,
}

StringReadContext :: struct {
    buffer: Byte_Buffer,
    source: string,
}

socket_reader_make :: proc (client: net.TCP_Socket, buffer: []u8) -> SocketReadContext {
    result: SocketReadContext
    result.buffer = make_byte_buffer(buffer)
    result.socket = client
    
    return result
}

////////////////////////////////////////////////

reader_receive :: proc (reader: ^SocketReadContext, at_most := max(int)) -> bool {
    ok := true
    if !buffer_can_read(&reader.buffer) {
        
        clear_byte_buffer(&reader.buffer)
        wanted_read := min(buffer_write_available(&reader.buffer), at_most)
        actual_read, read_error := net.recv_tcp(reader.socket, reader.buffer.bytes[:wanted_read])
        
        reader.buffer.write_cursor = actual_read
        
        if read_error != nil {
            ok = false
            fmt.printf("ERROR: Could not read from socket '%v': %v\n", address_and_port_from_socket(reader.socket), read_error)
        }
    }
    
    return ok
}

////////////////////////////////////////////////
// @naming if it werent for the I/O it would be more of a copy than a read

// @todo(viktor): can we remove the read-byte-write-byte loop like we did for read_count?
read_until :: proc { read_until_string, read_until_socket }
read_until_socket :: proc (destination: ^Byte_Buffer, reader: ^SocketReadContext, ending: string) -> bool {
    read_done: bool
    
    for !read_done {
        if !reader_receive(reader) do return false
        
        copy: for buffer_can_read(&reader.buffer) {
            it := buffer_read(&reader.buffer, u8)
            
            buffer_write(destination, it)
            if ends_with(buffer_peek_all_string(destination), ending) {
                read_done = true
                break copy
            }
        }
    }
    
    return true
}
read_until_string :: proc (destination: ^Byte_Buffer, reader: ^StringReadContext, ending: string) -> bool {
    read_done: bool
    
    for !read_done {
        copy: for buffer_can_read(&reader.buffer) {
            it := buffer_read(&reader.buffer, u8)
            
            buffer_write(destination, it)
            if ends_with(buffer_peek_all_string(destination), ending) {
                read_done = true
                break copy
            }
        }
        
        if !buffer_can_read(&reader.buffer) do return true
    }
    
    return true
}

read_count :: proc { read_count_string, read_count_socket }
read_count_socket :: proc (destination: ^Byte_Buffer, reader: ^SocketReadContext, count: int) -> bool {
    remaining := count
    for remaining != 0 {
        if !reader_receive(reader) do return false
        
        read_available  := buffer_read_available(&reader.buffer)
        write_available := buffer_write_available(destination)
        // @todo(viktor): do this check elsewhere as well
        if write_available == 0 do return false
        read_count := min(remaining, read_available, write_available)
        remaining -= read_count
        
        buffer_write_buffer_slice(destination, &reader.buffer, read_count)
    }
        
    return true
}
read_count_string :: proc (destination: ^Byte_Buffer, reader: ^StringReadContext, count: int) -> bool {
    remaining := count
    for remaining != 0 {
        available  := buffer_read_available(&reader.buffer)
        read_count := min(remaining, available)
        remaining -= read_count
        
        buffer_write_buffer_slice(destination, &reader.buffer, read_count)
        
        if !buffer_can_read(&reader.buffer) do return true
    }
        
    return true
}

read_done :: proc(reader: ^$T) -> bool {
    result: bool
    
    when T == SocketReadContext {
        actual_read, read_error := net.recv_tcp(reader.socket, nil) // Try to read zero bytes to see if the socket is still alive
        
        if actual_read != 0 || read_error != nil {
            // @todo(viktor): handle the error
            unimplemented()
        }
    }
    
    result = !buffer_can_read(&reader.buffer)
    return result
}
