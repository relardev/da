package game

import ts "core:container/topological_sort"
import "core:log"
import hm "handle_map"

Graph :: struct {
	nodes: hm.Handle_Map(Node, NodeHandle, 1024),
	edges: hm.Handle_Map(Edge, EdgeHandle, 1024),
}

NodeHandle :: hm.Handle
EdgeHandle :: hm.Handle

Node :: struct {
	handle:    NodeHandle,
	text:      string,
	position:  Vec2,
	width_px:  f32,
	height_px: f32,
	depth:     i32,
}

Edge :: struct {
	handle: EdgeHandle,
	from:   NodeHandle,
	to:     NodeHandle,
}

graph_calculate_layout :: proc(graph: ^Graph) {
	sorter: ts.Sorter(NodeHandle)
	ts.init(&sorter)
	defer ts.destroy(&sorter)

	node_iter := hm.make_iter(&g.graph.nodes)
	for node in hm.iter(&node_iter) {
		ok := ts.add_key(&sorter, node.handle)
		assert(ok, "Failed to add node to sorter")
	}

	edge_iter := hm.make_iter(&g.graph.edges)
	for edge in hm.iter(&edge_iter) {
		ok := ts.add_dependency(&sorter, edge.from, edge.to)
		assert(ok, "Failed to add edge dependency to sorter")
	}

	nodes, cycled := ts.sort(&sorter)

	assert(len(cycled) == 0, "Graph contains cycles")

	layers := make(
		map[NodeHandle]int,
		hm.num_used(graph.nodes),
		allocator = context.temp_allocator,
	)
	for node in nodes {
		max_prev := 0
		has_pred := false
		for u in graph_predecessors_of(graph, node) {
			has_pred = true
			if layers[u] + 1 > max_prev {
				max_prev = layers[u] + 1
			}
		}
		if has_pred {
			layers[node] = max_prev
		} else {
			layers[node] = 0
		}
	}

	log.info(layers)
}

graph_predecessors_of :: proc(graph: ^Graph, node: NodeHandle) -> []NodeHandle {
	edges_iter := hm.make_iter(&graph.edges)
	preds := make([dynamic]NodeHandle, 0, 16, allocator = context.temp_allocator)
	for edge in hm.iter(&edges_iter) {
		if edge.to == node {
			append(&preds, edge.from)
		}
	}
	return preds[:]
}
