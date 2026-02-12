package main

import "core:fmt"
import "core:net"

SocketReadContext :: struct {
    socket: net.TCP_Socket,
    
    _backing: [8] u8,
    buffer: Byte_Buffer,

    read_error: net.TCP_Recv_Error,
}

// @todo(viktor): currently only strings know when its done, and we only ever ask with the function for done, so kinda stupid
Read_Result :: enum { CanBeContinued, Done, ShouldClose }

////////////////////////////////////////////////

socket_read_until :: proc (reader: ^SocketReadContext, destination: ^Byte_Buffer, ending: string) -> Read_Result {
    for {
        begin_socket_read(reader)
        
        read_done := _read_ending_middle(destination, &reader.buffer, ending)
        
        continue_reading, read_result := end_socket_read(reader, read_done)
        if !continue_reading do return read_result
    }
}

socket_read_count :: proc (reader: ^SocketReadContext, destination: ^Byte_Buffer, count: int) -> Read_Result {
    for {
        begin_socket_read(reader, count)
        
        read_done := _read_count_middle(destination, &reader.buffer, count)
        
        continue_reading, read_result := end_socket_read(reader, read_done)
        if !continue_reading do return read_result
    }
}

socket_read_all :: proc (reader: ^SocketReadContext, destination: ^Byte_Buffer) -> Read_Result {
    for {
        begin_socket_read(reader)
        
        buffer_write_full_buffer(destination, &reader.buffer)
        
        continue_reading, read_result := end_socket_read(reader, false)
        if !continue_reading do return read_result
    }
}

socket_read_done :: proc(reader: ^SocketReadContext) -> bool {
    null: [0] u8
    read: int
    read, reader.read_error = net.recv_tcp(reader.socket, null[:])
    
    result: bool
    if read == 0 && reader.read_error == nil {
        result = reader.buffer.read_cursor == reader.buffer.write_cursor
    } else {
        // @todo(viktor): handle the error
    }
    return result
}

////////////////////////////////////////////////

begin_socket_read :: proc (reader: ^SocketReadContext, at_most := len(reader._backing)) {
    if !buffer_can_read(&reader.buffer) {
        read: int
        read, reader.read_error = net.recv_tcp(reader.socket, reader._backing[:min(len(reader._backing), at_most)])
        reader.buffer.write_cursor = read
        reader.buffer.read_cursor = 0
    }
}

end_socket_read :: proc (reader: ^SocketReadContext, pause_reading: bool) -> (bool, Read_Result) {
    continue_reading: bool
    result: Read_Result
    if reader.read_error != nil {
        end, _ := net.bound_endpoint(reader.socket)
        fmt.printf("ERROR: Could not read from socket '%v': %v\n", net.endpoint_to_string(end, context.temp_allocator), reader.read_error)
        result = .ShouldClose
    } else if pause_reading {
        result = .CanBeContinued
    } else {
        continue_reading = true
    }
    
    return continue_reading, result
}

////////////////////////////////////////////////

StringReadContext :: struct {
    backing: string,
    buffer: Byte_Buffer,
}

string_read_until:: proc (reader: ^StringReadContext, buffer: ^Byte_Buffer, ending: string) -> Read_Result {
    for {
        read_done := _read_ending_middle(buffer, &reader.buffer, ending)
        
        if !buffer_can_read(&reader.buffer) do return .Done
        if read_done do return .CanBeContinued 
    }
}

string_read_count :: proc (reader: ^StringReadContext, buffer: ^Byte_Buffer, count: int) -> Read_Result {
    for {
        read_done := _read_count_middle(buffer, &reader.buffer, count)
        
        if !buffer_can_read(&reader.buffer) do return .Done
        if read_done do return .CanBeContinued 
    }
}

string_read_all :: proc (reader: ^StringReadContext, buffer: ^Byte_Buffer) -> Read_Result {
    buffer_write_full_buffer(buffer, &reader.buffer)
    return .Done
}

string_read_done :: proc(reader: ^StringReadContext) -> bool {
    return reader.buffer.read_cursor == reader.buffer.write_cursor
}

////////////////////////////////////////////////

_read_ending_middle :: proc (destination, source: ^Byte_Buffer, ending: string) -> bool {
    read_done: bool
    copy: for buffer_can_read(source) {
        it := buffer_read(source, u8)^
        
        buffer_write(destination, it)
        if ends_with(buffer_peek_all_string(destination), ending) {
            read_done = true
            break copy
        }
    }
    
    return read_done
}

_read_count_middle :: proc (destination, source: ^Byte_Buffer, count: int) -> bool {
    // @todo(viktor): handle this nicer in the loop
    if count == 0 do return true
    
    read_done: bool
    start := destination.write_cursor
    copy: for buffer_can_read(source) {
        it := buffer_read(source, u8)^
        
        buffer_write(destination, it)
        if destination.write_cursor - start == count {
            read_done = true
            break copy
        }
    }
    
    return read_done
}