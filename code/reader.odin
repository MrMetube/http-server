package main

import "core:fmt"
import "core:net"

SocketReadContext :: struct {
    socket: net.TCP_Socket,
    
    backing: [8] u8,
    buffer:   Byte_Buffer,

    read_error: net.TCP_Recv_Error,
}

StringReadContext :: struct {
    backing: string,
    buffer:  Byte_Buffer,
}

socket_reader_make :: proc (client: net.TCP_Socket) -> SocketReadContext {
    result: SocketReadContext
    result.buffer = make_byte_buffer(result.backing[:])
    result.socket = client
    return result
}

////////////////////////////////////////////////

begin_socket_read :: proc (reader: ^SocketReadContext, at_most := len(reader.backing)) {
    if !buffer_can_read(&reader.buffer) {
        wants_to_read := min(len(reader.backing), at_most)
        
        reader.buffer.write_cursor, reader.read_error = net.recv_tcp(reader.socket, reader.buffer.bytes[:wants_to_read])
        reader.buffer.read_cursor = 0
    }
}

end_socket_read :: proc (reader: ^SocketReadContext) -> bool {
    ok := reader.read_error == nil
    if !ok {
        end, _ := net.bound_endpoint(reader.socket)
        fmt.printf("ERROR: Could not read from socket '%v': %v\n", net.endpoint_to_string(end, context.temp_allocator), reader.read_error)
    }
    
    return ok
}

////////////////////////////////////////////////

// @todo(viktor): fix the loops, for !read_done
read_until :: proc (reader: ^$T, destination: ^Byte_Buffer, ending: string) -> bool {
    read_done: bool
    
    for !read_done {
        when T == SocketReadContext {
            begin_socket_read(reader)
        }
        
        copy: for buffer_can_read(&reader.buffer) {
            it := buffer_read_value(&reader.buffer, u8)
            
            buffer_write(destination, it)
            if ends_with(buffer_peek_all_string(destination), ending) {
                read_done = true
                break copy
            }
        }
        
        when T == SocketReadContext {
            if !end_socket_read(reader) do return false
        } else {
            if !buffer_can_read(&reader.buffer) do return true
        }
    }
    
    return true
}

read_count :: proc (reader: ^$T, destination: ^Byte_Buffer, count: int) -> bool {
    read_done: bool
    
    for !read_done {
        when T == SocketReadContext {
            begin_socket_read(reader, count)
        }
        
        // @todo(viktor): handle this nicer in the loop
        if count == 0 {
            read_done = true
        } else {
            start := destination.write_cursor
            copy: for buffer_can_read(&reader.buffer) {
                it := buffer_read(&reader.buffer, u8)^
                
                buffer_write(destination, it)
                if destination.write_cursor - start == count {
                    read_done = true
                    break copy
                }
            }
        }
        
        when T == SocketReadContext {
            if !end_socket_read(reader) do return false
        } else {
            if !buffer_can_read(&reader.buffer) do return true
        }
    }
        
    return true
}

read_done :: proc(reader: ^$T) -> bool {
    result: bool
    
    when T == SocketReadContext {
        read: int
        read, reader.read_error = net.recv_tcp(reader.socket, nil) // Try to read zero bytes to see if the socket is still alive
        
        if !(read == 0 && reader.read_error == nil) {
            // @todo(viktor): handle the error
            unimplemented()
        }
    }
    
    result = reader.buffer.read_cursor == reader.buffer.write_cursor
    
    return result
}
