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

write_reserve :: proc (b: ^Byte_Buffer, $T: typeid) -> (result: ^T) {
    dest := b.bytes[b.write_cursor:]
    size := size_of(T)
    assert(len(dest) >= size)
    
    result = cast(^T) &dest[0]
    b.write_cursor += size
    
    return result
}

write_slice :: proc (b: ^Byte_Buffer, values: [] $T) {
    dest := b.bytes[write_cursor:]
    assert(len(dest) >= len(source))
    source := slice_from_parts(u8, raw_data(values), len(values) * size_of(T))
    copy(dest, source)
    b.write_cursor += len(source)
}

write :: proc (b: ^Byte_Buffer, value: $T) {
    dest := b.bytes[write_cursor:]
    assert(len(dest) >= size_of(T))
    value := value
    source := slice_from_parts(u8, &value, size_of(T))
    copy(dest, source)
    b.write_cursor += len(source)
}

write_align :: proc (b: ^Byte_Buffer, #any_int alignment: int) {
    // @todo(viktor): ensure that alignment is a power of two
    remainder := b.write_cursor % alignment
    if b.write_cursor % alignment != 0 {
        offset := alignment - remainder
        assert(b.write_cursor + offset < len(b.bytes))
        b.write_cursor += offset
    }
}

read_align :: proc (b: ^Byte_Buffer, #any_int alignment: int) {
    // @todo(viktor): ensure that alignment is a power of two
    remainder := b.read_cursor % alignment
    if b.read_cursor % alignment != 0 {
        offset := alignment - remainder
        assert(b.read_cursor + offset < len(b.bytes))
        b.read_cursor += offset
    }
}

read :: proc (b: ^Byte_Buffer, $T: typeid) -> (result: ^T) {
    source := b.bytes[b.read_cursor:]
    assert(size_of(T) <= len(source))
    
    result = cast(^T) &source[0]
    b.read_cursor += size_of(T)
    
    return result
}

read_slice :: proc (b: ^Byte_Buffer, $T: typeid/ [] $E, count: int) -> (result: [] E) {
    size := count * size_of(T)
    source := b.bytes[b.read_cursor:]
    assert(size <= len(source))
    result = source[:size]
    b.read_cursor += size
    
    return result
}

begin_reading :: proc (b: ^Byte_Buffer) { b.read_cursor = 0 }
can_read :: proc (b: ^Byte_Buffer) -> (result: bool) { return b.read_cursor < b.write_cursor }

clear_byte_buffer :: proc (b: ^Byte_Buffer) {
    b.read_cursor = 0
    b.write_cursor = 0
}
