package graph_layout2

import "base:runtime"
import "core:log"
import "core:mem"
import ts "topological_sort"

_ :: log
_ :: ts

V2 :: [2]f32
V2i :: [2]i32

Graph :: struct {
	allocator:           mem.Allocator,
	nodes:               #soa[]Node,
	edges:               #soa[]Edge,
	external_id_to_node: map[ExternalID]NodeHandle,
	node_size:           V2,
}

EdgeHandle :: struct {
	offset: u16,
}

NodeHandle :: struct {
	offset: u16,
}

Node :: struct {
	external_id: ExternalID,
	in_edges:    EdgeHandle,
	out_edges:   EdgeHandle,
}

Edge :: struct {
	src:      NodeHandle,
	src_next: EdgeHandle,
	src_prev: EdgeHandle,
	dst:      NodeHandle,
	dst_next: EdgeHandle,
	dst_prev: EdgeHandle,
}

ExternalID :: u64

graph_init :: proc(
	g: ^Graph,
	node_capacity: i32,
	edge_capacity: i32,
	node_size: V2,
	allocator: mem.Allocator,
) {
	g.allocator = allocator
	g.nodes = make(#soa[]Node, node_capacity + 1, allocator)
	g.edges = make(#soa[]Edge, edge_capacity + 1, allocator)
	g.external_id_to_node = make(
		map[ExternalID]NodeHandle,
		int(f32(node_capacity) * 1.5),
		allocator,
	)
	g.node_size = node_size
}

graph_node_add :: proc(g: ^Graph, id: ExternalID) -> bool {
	return false
}

graph_edge_add :: proc(g: ^Graph, from_id, to_id: ExternalID) -> bool {
	return false
}

graph_layout_compute :: proc(g: ^Graph) {
	return
}

graph_node_read :: proc(g: ^Graph, id: ExternalID) -> (V2, bool) {
	return {0, 0}, true
}

graph_edge_read :: proc(g: ^Graph, from_id, to_id: ExternalID) -> ^Edge {
	return nil
}
