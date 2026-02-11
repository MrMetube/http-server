package main

import "base:runtime"

pmm :: rawptr
umm :: uintptr

slice_from_parts :: proc { slice_from_parts_cast, slice_from_parts_direct }
slice_from_parts_cast :: proc "contextless" ($T: typeid, data: pmm, #any_int count: i64) -> []T {
    // :PointerArithmetic
    return (cast([^]T)data)[:count]
}
slice_from_parts_direct :: proc "contextless" (data: ^$T, #any_int count: i64) -> []T {
    // :PointerArithmetic
    return (cast([^]T)data)[:count]
}

Allocator :: runtime.Allocator

////////////////////////////////////////////////

chop_until :: proc (data: ^string, until: u8) -> (string, bool) #optional_ok {
    ok: bool
    index: int
    for ; index <len(data); index += 1 {
        if data[index] == until {
            ok = true
            break
        }
    }
    
    result := data[:index]
    if index+1 < len(data) {
        data^ = data[index+1:]
    } else {
        data^ = ""
    }
    
    return result, ok
}

chop_until_space :: proc (data: ^string) -> (string, bool) #optional_ok {
    // @copypasta from chop_until
    ok: bool
    index: int
    for ; index <len(data); index += 1 {
        if is_space(data[index]) {
            ok = true
            break
        }
    }
    
    result := data[:index]
    if index+1 < len(data) {
        data^ = data[index+1:]
    } else {
        data^ = ""
    }
    
    return result, ok
}

chop_until_string :: proc (data: ^string, ending: string) -> (string, bool) #optional_ok {
    // @copypasta from chop_until
    ok: bool
    index: int
    for ; index <len(data); index += 1 {
        // @speed this could be improved for longer endings
        if ends_with(data[:index], ending) {
            ok = true
            break
        }
    }
    
    result := data[:index]
    if index+1 < len(data) {
        data^ = data[index+1:]
    } else {
        data^ = ""
    }
    
    return result, ok
}

////////////////////////////////////////////////

ends_with :: proc (s, ending: string) -> bool {
    result: bool
    if len(s) >= len(ending) {
        result = s[len(s)-len(ending):] == ending
    }
    return result
}

////////////////////////////////////////////////

trim :: proc (data: string) -> string {
    result := data
    result = trim_left(result)
    result = trim_right(result)
    return result
}
trim_right :: proc (data: string) -> string {
    result := data
    for len(result) > 0 && is_space(result[len(result)-1]) do result = result[:len(result)-1]
    return result
}
trim_left :: proc (data: string) -> string {
    result := data
    for len(result) > 0 && is_space(result[0]) do result = result[1:]
    return result
}

////////////////////////////////////////////////

is_space :: proc (char: u8) -> bool {
    result: bool
    switch char {
    case ' ', '\t', '\n', '\r', '\v': result = true
    }
    return result
}

////////////////////////////////////////////////

to_string :: proc (data: [] u8) -> string {
    return transmute(string) data
}
to_bytes :: proc (data: string) -> [] u8 {
    return transmute([] u8) data
}
