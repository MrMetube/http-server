package main

////////////////////////////////////////////////
// @note(viktor): writing and reading need to be in sync or we get undefined behaviour. We could always write the type of a value in combination with that value and then on read assert that the next type to read is the same as the requested type of the parameter.

Byte_Buffer :: struct {
    bytes:        [] u8,
    read_cursor:  int,
    write_cursor: int,
}

make_byte_buffer :: proc (buffer: [] u8) -> (result: Byte_Buffer) {
    result = { bytes = buffer }
    return result
}

buffer_write_reserve :: proc (b: ^Byte_Buffer, $T: typeid) -> (result: ^T) {
    dest := b.bytes[b.write_cursor:]
    size := size_of(T)
    assert(len(dest) >= size)
    
    result = cast(^T) &dest[0]
    b.write_cursor += size
    
    return result
}

buffer_write_buffer :: proc (b: ^Byte_Buffer, source: ^Byte_Buffer) {
    ss := buffer_read_all(source)
    buffer_write_slice(b, ss)
}

buffer_write_buffer_slice :: proc (b: ^Byte_Buffer, source: ^Byte_Buffer, count: int) {
    ss := buffer_read_slice(source, count)
    buffer_write_slice(b, ss)
}

buffer_write_string :: proc (b: ^Byte_Buffer, s: string) {
    buffer_write_slice(b, transmute([] u8) s)
}

buffer_write_slice :: proc (b: ^Byte_Buffer, values: [] $T) {
    assert(size_of(T) * len(values) <= buffer_write_available(b))
    
    dest   := b.bytes[b.write_cursor:]
    source := slice_from_parts(u8, raw_data(values), len(values) * size_of(T))
    
    copy(dest, source)
    b.write_cursor += len(source)
}

buffer_write :: proc (b: ^Byte_Buffer, value: ^$T) {
    assert(size_of(T) <= buffer_write_available(b))
    
    assert(b != nil)
    assert(b.bytes != nil)
    
    source := slice_from_parts(u8, value, size_of(T))
    copy(b.bytes[b.write_cursor:], source)
    
    b.write_cursor += len(source)
}

////////////////////////////////////////////////

buffer_align_read_cursor :: proc (b: ^Byte_Buffer, #any_int alignment: int) {
    buffer_align_cursor(b, alignment, &b.read_cursor)
}

buffer_align_write_cursor :: proc (b: ^Byte_Buffer, #any_int alignment: int) {
    buffer_align_cursor(b, alignment, &b.write_cursor)
}

buffer_align_cursor :: proc (b: ^Byte_Buffer, #any_int alignment: int, cursor: ^int) {
    // @todo(viktor): ensure that alignment is a power of two
    remainder := cursor^ % alignment
    if cursor^ % alignment != 0 {
        offset := alignment - remainder
        assert(cursor^ + offset < len(b.bytes))
        cursor^ += offset
    }
}

////////////////////////////////////////////////

buffer_read :: proc (b: ^Byte_Buffer, $T: typeid) -> (result: ^T) {
    data := buffer_read_slice(b, size_of(T))
    result = cast(^T) &data[0]
    return result
}

buffer_read_copy :: proc (b: ^Byte_Buffer, $T: typeid) -> (result: T) {
    data := buffer_read_slice(b, size_of(T))
    result = (cast(^T) &data[0])^
    return result
}

buffer_read_all :: proc (b: ^Byte_Buffer) -> (result: [] u8) {
    result = buffer_read_slice(b, b.write_cursor - b.read_cursor)
    return result
}

buffer_read_all_string :: proc (b: ^Byte_Buffer) -> (result: string) {
    result = transmute(string) buffer_read_slice(b, b.write_cursor - b.read_cursor)
    return result
}

buffer_read_slice :: proc (b: ^Byte_Buffer, count: int) -> (result: [] u8) {
    result = buffer_peek_slice(b, count)
    b.read_cursor += count
    return result
}

////////////////////////////////////////////////

buffer_peek_all_string :: proc (b: ^Byte_Buffer) -> (result: string) {
    bytes := buffer_peek_slice(b, buffer_read_available(b))
    result = transmute(string) bytes
    return result
}

buffer_peek_slice :: proc (b: ^Byte_Buffer, count: int) -> (result: [] u8) {
    assert(count <= buffer_read_available(b))
    result = b.bytes[b.read_cursor:][:count]
    return result
}

////////////////////////////////////////////////

buffer_begin_reading :: proc (b: ^Byte_Buffer) { b.read_cursor = 0 }
buffer_can_read :: proc (b: ^Byte_Buffer) -> (result: bool) { return b.read_cursor < b.write_cursor }

buffer_read_available  :: proc (b: ^Byte_Buffer) -> int { return b.write_cursor - b.read_cursor  }
buffer_write_available :: proc (b: ^Byte_Buffer) -> int { return len(b.bytes)   - b.write_cursor }

buffer_foo :: proc (b: ^Byte_Buffer) {
    unread := b.bytes[b.read_cursor:b.write_cursor]
    copy(b.bytes[0:len(unread)], unread)
    
    b.write_cursor -= b.read_cursor
    b.read_cursor   = 0
}

clear_byte_buffer :: proc (b: ^Byte_Buffer) {
    b.read_cursor = 0
    b.write_cursor = 0
}
