package graph_layout

import "core:fmt"
import "core:mem"

_ :: mem

print_allocator :: proc(allocator: ^mem.Allocator) -> mem.Allocator {
	return mem.Allocator{procedure = print_allocator_proc, data = allocator}
}

print_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size: int,
	alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	allocator := cast(^mem.Allocator)allocator_data

	fmt.println(loc, size, alignment)

	bytes, err := allocator.procedure(
		allocator.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		loc,
	)
	return bytes, err
}
