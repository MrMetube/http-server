package main

////////////////////////////////////////////////
// @note(viktor): writing and reading need to be in sync or we get undefined behaviour. We could always write the type of a value in combination with that value and then on read assert that the next type to read is the same as the requested type of the parameter.
// @todo(viktor): most of these calls are untested and need to checked and verified

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

buffer_write_slice :: proc (b: ^Byte_Buffer, values: [] $T) {
    dest   := b.bytes[b.write_cursor:]
    source := slice_from_parts(u8, raw_data(values), len(values) * size_of(T))
    assert(len(dest) >= len(source))
    
    copy(dest, source)
    b.write_cursor += len(source)
}

buffer_write_string :: proc (b: ^Byte_Buffer, s: string) {
    buffer_write_slice(b, transmute([] u8) s)
}

buffer_write :: proc (b: ^Byte_Buffer, value: $T) {
    dest := b.bytes[b.write_cursor:]
    assert(len(dest) >= size_of(T))
    value := value
    source := slice_from_parts(u8, &value, size_of(T))
    copy(dest, source)
    b.write_cursor += len(source)
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
buffer_align_read_cursor :: proc (b: ^Byte_Buffer, #any_int alignment: int) {
    buffer_align_cursor(b, alignment, &b.read_cursor)
}
buffer_align_write_cursor :: proc (b: ^Byte_Buffer, #any_int alignment: int) {
    buffer_align_cursor(b, alignment, &b.write_cursor)
}

buffer_read :: proc (b: ^Byte_Buffer, $T: typeid) -> (result: ^T) {
    data := buffer_read_amount(b, size_of(T))
    result = cast(^T) &data[0]
    return result
}

buffer_read_all :: proc (b: ^Byte_Buffer) -> (result: [] u8) {
    result = buffer_read_amount(b, b.write_cursor - b.read_cursor)
    return result
}
buffer_read_all_string :: proc (b: ^Byte_Buffer) -> (result: string) {
    result = transmute(string) buffer_read_amount(b, b.write_cursor - b.read_cursor)
    return result
}
buffer_read_amount :: proc (b: ^Byte_Buffer, count: int) -> (result: [] u8) {
    result = buffer_peek_amount(b, count)
    b.read_cursor += count
    return result
}

buffer_peek_all_string :: proc (b: ^Byte_Buffer) -> (result: string) {
    result = transmute(string) buffer_peek_amount(b, b.write_cursor - b.read_cursor)
    return result
}

buffer_peek_amount :: proc (b: ^Byte_Buffer, count: int) -> (result: [] u8) {
    source := b.bytes[b.read_cursor:b.write_cursor]
    assert(count <= len(source))
    result = source[:count]
    return result
}

buffer_read_slice :: proc (b: ^Byte_Buffer, $T: typeid/ [] $E, count: int) -> (result: [] E) {
    data := buffer_read_amount(b, count * size_of(E))
    result = slice_from_parts(E, raw_data(data), count)
    return result
}

buffer_begin_reading :: proc (b: ^Byte_Buffer) { b.read_cursor = 0 }
buffer_can_read :: proc (b: ^Byte_Buffer) -> (result: bool) { return b.read_cursor < b.write_cursor }

clear_byte_buffer :: proc (b: ^Byte_Buffer) {
    b.read_cursor = 0
    b.write_cursor = 0
}
