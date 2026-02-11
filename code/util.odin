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