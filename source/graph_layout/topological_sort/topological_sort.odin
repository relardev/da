package topological_sort

import "base:intrinsics"
import "base:runtime"


Relations :: struct($K: typeid) where intrinsics.type_is_valid_map_key(K) {
	dependents:   map[K]bool,
	dependencies: int,
}

Sorter :: struct(K: typeid) where intrinsics.type_is_valid_map_key(K) {
	relations:            map[K]Relations(K),
	dependents_allocator: runtime.Allocator,
}


init :: proc(
	sorter: ^$S/Sorter($K),
	number_of_nodes: int,
	allocator := context.allocator,
	loc := #caller_location,
) {
	sorter.relations = make(
		map[K]Relations(K),
		(4 * number_of_nodes + 2) / 3, // cause map resizing treshold is 75% of capacity
		allocator = allocator,
	)
	sorter.dependents_allocator = allocator
}

destroy :: proc(sorter: ^$S/Sorter($K)) {
	for _, v in sorter.relations {
		delete(v.dependents)
	}
	delete(sorter.relations)
}

add_key :: proc(sorter: ^$S/Sorter($K), key: K, expected_dependencies: int = 0) {
	sorter.relations[key] = make_relations(sorter, expected_dependencies)
}

add_dependency :: proc(sorter: ^$S/Sorter($K), key, dependency: K) -> bool {
	if key == dependency {
		return false
	}

	find := &sorter.relations[dependency]
	assert(find != nil, "Dependency not found")

	if find.dependents[key] {
		return true
	}
	find.dependents[key] = true

	find = &sorter.relations[key]
	assert(find != nil, "Key not found")

	find.dependencies += 1

	return true
}

sort :: proc(
	sorter: ^$S/Sorter($K),
	result_allocator := context.allocator,
) -> (
	sorted: [dynamic]K,
	cycled: bool,
) {
	relations := &sorter.relations
	sorted = make([dynamic]K, 0, len(sorter.relations), allocator = result_allocator)

	for k, v in relations {
		if v.dependencies == 0 {
			append(&sorted, k)
		}
	}

	for root in sorted {
		for k, _ in relations[root].dependents {
			relation := &relations[k]
			relation.dependencies -= 1
			if relation.dependencies == 0 {
				append(&sorted, k)
			}
		}
	}

	for _, v in relations {
		if v.dependencies != 0 {
			return nil, true
		}
	}

	return sorted, false
}

@(private = "file")
make_relations :: proc(sorter: ^$S/Sorter($K), map_size: int) -> Relations(K) {
	return Relations(K) {
		dependents = make(map[K]bool, map_size, allocator = sorter.dependents_allocator),
	}
}
