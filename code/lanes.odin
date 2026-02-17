package main

import "core:sync"

thread_context: ThreadContext

ThreadContext :: struct {
    barrier:    sync.Barrier,
    lane_count: i64,
    
    broadcast_memory: pmm,
    broadcast_slice:  [] u8,
}

@(thread_local) thread_index: i64

LaneRange :: struct {
    min, max: i64,
}

////////////////////////////////////////////////

thread_context_init :: proc (thread_count: i64) {
    thread_context.lane_count = thread_count
    sync.barrier_init(&thread_context.barrier, auto_cast thread_count)
}

thread_init :: proc (init_thread_index: i64) {
    thread_index = init_thread_index
}

////////////////////////////////////////////////

lane_index :: proc () -> (result: i64) {
    result = thread_index
    return result
}

////////////////////////////////////////////////

lane_sync :: proc { lane_sync_barrier, lane_sync_slice, lane_sync_value }

lane_sync_barrier :: proc () {
    sync.barrier_wait(&thread_context.barrier)
}

lane_sync_value :: proc (value: ^$T, source_lane_index: i64 = 0) /* where size_of(T) <= size_of(pmm) */ {
    if lane_index() == source_lane_index {
        thread_context.broadcast_memory = cast(pmm) value
    }
    lane_sync()
    
    if lane_index() != source_lane_index {
        #assert(type_of(value^) == T)
        value^ = (cast(^T) thread_context.broadcast_memory)^
    }
    lane_sync()
}

lane_sync_slice :: proc (slice: ^[] $T, source_lane_index: i64 = 0) {
    if lane_index() == source_lane_index {
        thread_context.broadcast_slice = transmute(type_of(thread_context.broadcast_slice)) slice^
    }
    lane_sync()
    
    if lane_index() != source_lane_index {
        slice^ = transmute(type_of(slice^)) thread_context.broadcast_slice
    }
    lane_sync()
}

////////////////////////////////////////////////

lane_range :: proc { lane_range_slice, lane_range_count }
lane_range_slice :: proc (slice: []$T) -> (result: [] T) {
    range := lane_range(len(slice))
    result = slice[range.min:range.max]
    return result
}
lane_range_count :: proc (#any_int count: i64) -> (result: LaneRange) {
    count_per_lane  := count / thread_context.lane_count
    leftovers_count := count % thread_context.lane_count
    
    thread_has_leftovers         := thread_index < leftovers_count
    leftovers_before_this_thread := thread_has_leftovers ? thread_index : leftovers_count
    leftovers_for_this_thread    := thread_has_leftovers ? cast(i64) 1  : 0
    
    lane_first_index         := thread_index     * count_per_lane + leftovers_before_this_thread
    lane_one_past_last_index := lane_first_index + count_per_lane + leftovers_for_this_thread
    
    result.min = lane_first_index
    result.max = lane_one_past_last_index
    
    /*
        alt: LaneRange
        a := thread_index
        p := count_per_lane
        r := leftovers_count
        c := thread_has_leftovers ? a   : r
        d := thread_has_leftovers ? a+1 : r
        alt.min =  a    * p + c
        alt.max = (a+1) * p + d
        assert(alt == result) 
    */
    
    return result
}
