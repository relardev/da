package game

import clay "clay-odin"
import "core:fmt"
import gl "graph_layout"
import hm "handle_map"

Graph :: struct {
	nodes:              hm.Handle_Map(Node, NodeHandle, 1024),
	edges:              hm.Handle_Map(Edge, EdgeHandle, 1024),
	// debug drawing
	draw_gutters:       bool,
	draw_nodes:         bool,
	gutters_vertical:   []gl.Gutter,
	gutters_horizontal: []gl.Gutter,
}

NodeHandle :: hm.Handle
EdgeHandle :: hm.Handle

Node :: struct {
	handle:      NodeHandle,
	clay_id:     clay.ElementId,
	is_if_node:  bool,
	// display stuff
	name:        string,
	type:        string,
	arguments:   []Argument,
	// filled by clay layouting
	size_px:     Vec2,
	// filled by graph layouting
	position_px: Vec2,
}

Argument :: struct {
	text:      string,
	long_text: string,
	clay_id:   clay.ElementId,
}

Edge :: struct {
	handle:          EdgeHandle,
	from:            NodeHandle,
	to:              NodeHandle,
	// filled by graph layouting
	segments:        []Vec2, // points in pixels
	arrow_direction: gl.ArrowDirection,
}

graph_clay_connected_nodes :: proc(
	graph: ^Graph,
	node_handle: NodeHandle,
	allocator := context.allocator,
) -> []clay.ElementId {
	edges_iter := hm.make_iter(&graph.edges)
	preds := make([dynamic]clay.ElementId, 0, 16, allocator = allocator)
	for edge in hm.iter(&edges_iter) {
		if edge.to == node_handle {
			node := hm.get(&graph.nodes, edge.from)
			append(&preds, node.clay_id)
		}
		if edge.from == node_handle {
			node := hm.get(&graph.nodes, edge.to)
			append(&preds, node.clay_id)
		}
	}
	return preds[:]
}

graph_edges_of :: proc(
	graph: ^Graph,
	node: NodeHandle,
	allocator := context.allocator,
) -> []EdgeHandle {
	edges := make([dynamic]EdgeHandle, 0, 16, allocator = allocator)

	edges_iter := hm.make_iter(&graph.edges)
	for edge in hm.iter(&edges_iter) {
		if edge.from == node || edge.to == node {
			append(&edges, edge.handle)
		}
	}

	return edges[:]
}

argument_create :: proc(original_text: string, id: ^i32) -> Argument {
	long_text: string
	text := original_text
	if len(text) > 90 {
		long_text = text
		text = fmt.aprintf("%s...", text[:90], allocator = g.recipe_allocator)
	}

	our_id := id^
	id^ = our_id + 1

	return Argument {
		text = text,
		long_text = long_text,
		clay_id = clay.ID("NodeAttribute", u32(our_id)),
	}
}
