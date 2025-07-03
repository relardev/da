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
	handle:      NodeHandle,
	text:        string,
	position:    Vec2i,
	position_px: Vec2,
	width_px:    f32,
	height_px:   f32,
	depth:       i32,
}

Edge :: struct {
	handle: EdgeHandle,
	from:   NodeHandle,
	to:     NodeHandle,
}

graph_calculate_layout :: proc(graph: ^Graph) {
	sorter: ts.Sorter(NodeHandle)
	context.allocator = context.temp_allocator
	ts.init(&sorter)
	defer ts.destroy(&sorter)

	node_iter := hm.make_iter(&g.graph.nodes)
	for node in hm.iter(&node_iter) {
		ok := ts.add_key(&sorter, node.handle)
		assert(ok, "Failed to add node to sorter")
	}

	edge_iter := hm.make_iter(&g.graph.edges)
	for edge in hm.iter(&edge_iter) {
		ok := ts.add_dependency(&sorter, edge.to, edge.from)
		assert(ok, "Failed to add edge dependency to sorter")
	}

	nodes_sorted, cycled := ts.sort(&sorter)

	assert(len(cycled) == 0, "Graph contains cycles")

	layers := make(map[NodeHandle]i32, hm.num_used(graph.nodes))
	for node in nodes_sorted {
		max_prev: i32 = 0
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
			log.info("Node without predecessors:", node)
			layers[node] = 0
		}
	}

	for node_handle, layer in layers {
		node := hm.get(&graph.nodes, node_handle)
		node.position.y = layer
		node.position_px.y = f32(node.position.y) * 100
	}

	layer_filling := make(map[i32][dynamic]NodeHandle)
	for node_handle in layers {
		node := hm.get(&graph.nodes, node_handle)
		layer := layer_filling[node.position.y]
		append(&layer, node_handle)
		layer_filling[node.position.y] = layer
	}

	for _, nodes in layer_filling {
		for node_handle, idx in nodes {
			node := hm.get(&graph.nodes, node_handle)
			node.position.x = i32(idx)
			node.position_px.x = f32(node.position.x) * 100
		}
	}
}

graph_predecessors_of :: proc(graph: ^Graph, node: NodeHandle) -> []NodeHandle {
	edges_iter := hm.make_iter(&graph.edges)
	preds := make([dynamic]NodeHandle, 0, 16)
	for edge in hm.iter(&edges_iter) {
		if edge.to == node {
			append(&preds, edge.from)
		}
	}
	return preds[:]
}
