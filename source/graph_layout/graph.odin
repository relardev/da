package graph_layout

import hm "../handle_map"
import ts "core:container/topological_sort"
import "core:mem"
import "core:slice"

gutter_edge_distance :: 10.0 // distance between edges in gutters
gutter_padding :: 40.0 // padding around gutters

GRAPH_X_ALGORITHM :: "naive" // "naive", "barycenter"

V2 :: [2]f32
V2i :: [2]i32

Graph :: struct {
	allocator:          mem.Allocator,
	nodes:              hm.Handle_Map(Node, NodeHandle, 1024),
	edges:              hm.Handle_Map(Edge, EdgeHandle, 1024),
	gutters_vertical:   [dynamic]Gutter,
	gutters_horizontal: [dynamic]Gutter,
	node_size:          V2,
}

NodeHandle :: hm.Handle

ExternalID :: u64

Node :: struct {
	handle:      NodeHandle,
	external_id: ExternalID,
	position:    V2i,
	position_px: V2,
}

EdgeHandle :: hm.Handle

ArrowDirection :: enum {
	Down,
	Left,
	Right,
}

Edge :: struct {
	handle:          EdgeHandle,
	from:            NodeHandle,
	to:              NodeHandle,
	segments:        [5]V2,
	arrow_direction: ArrowDirection,
}

Gutter :: struct {
	edges:   [dynamic]EdgeHandle,
	pos:     f32,
	size_px: f32,
}

graph_new :: proc(allocator := context.allocator) -> Graph {
	return Graph{allocator = allocator}
}

graph_free :: proc(graph: ^Graph) {
	for gutter in graph.gutters_vertical {
		delete(gutter.edges)
	}
	delete(graph.gutters_vertical)

	for gutter in graph.gutters_horizontal {
		delete(gutter.edges)
	}
	delete(graph.gutters_horizontal)
}

destroy_graph :: proc(graph: ^Graph) {
	if graph == nil {
		return
	}

	free(graph)
}

graph_add_node :: proc(graph: ^Graph, external_id: ExternalID, size: V2) {
	hm.add(&graph.nodes, Node{external_id = external_id})
	if graph.node_size.x < size.x {
		graph.node_size.x = size.x
	}

	if graph.node_size.y < size.y {
		graph.node_size.y = size.y
	}
}

graph_add_edge :: proc(graph: ^Graph, from: ExternalID, to: ExternalID) -> bool {
	// find from handle
	from_handle: NodeHandle
	FIND_FROM: {
		node_iter := hm.make_iter(&graph.nodes)
		for node in hm.iter(&node_iter) {
			if node.external_id == from {
				from_handle = node.handle
				break FIND_FROM
			}
		}

		return false
	}


	// find to handle
	to_handle: NodeHandle
	FIND_TO: {
		node_iter := hm.make_iter(&graph.nodes)
		for node in hm.iter(&node_iter) {
			if node.external_id == to {
				to_handle = node.handle
				break FIND_TO
			}
		}

		return false
	}

	if from_handle == to_handle {
		return false // self-loop, not allowed
	}

	hm.add(&graph.edges, Edge{from = from_handle, to = to_handle})
	return true
}

graph_read_node :: proc(graph: ^Graph, external_id: ExternalID) -> (V2, bool) {
	node_iter := hm.make_iter(&graph.nodes)
	for node in hm.iter(&node_iter) {
		if node.external_id == external_id {
			return node.position_px, true
		}
	}
	return {}, false
}

EdgeResult :: struct {
	segments:        []V2,
	arrow_direction: ArrowDirection,
}

graph_read_edge :: proc(graph: ^Graph, from: ExternalID, to: ExternalID) -> (EdgeResult, bool) {
	// find from handle
	from_handle: NodeHandle
	FIND_FROM: {
		node_iter := hm.make_iter(&graph.nodes)
		for node in hm.iter(&node_iter) {
			if node.external_id == from {
				from_handle = node.handle
				break FIND_FROM
			}
		}

		return {}, false
	}

	// find to handle
	to_handle: NodeHandle
	FIND_TO: {
		node_iter := hm.make_iter(&graph.nodes)
		for node in hm.iter(&node_iter) {
			if node.external_id == to {
				to_handle = node.handle
				break FIND_TO
			}
		}

		return {}, false
	}

	edge_iter := hm.make_iter(&graph.edges)
	for edge in hm.iter(&edge_iter) {
		if edge.from == from_handle && edge.to == to_handle {
			return EdgeResult{segments = edge.segments[:], arrow_direction = edge.arrow_direction},
				true
		}
	}

	return {}, false // edge not found
}

graph_calculate_layout :: proc(graph: ^Graph) -> (graph_size: V2) {
	sorter: ts.Sorter(NodeHandle)
	context.allocator = graph.allocator

	ts.init(&sorter)
	defer ts.destroy(&sorter)

	node_iter := hm.make_iter(&graph.nodes)
	for node in hm.iter(&node_iter) {
		// log.info("Adding node to sorter: ", node.handle, " - ", node.name)
		ok := ts.add_key(&sorter, node.handle)
		assert(ok, "Failed to add node to sorter")
	}

	edge_iter := hm.make_iter(&graph.edges)
	for edge in hm.iter(&edge_iter) {
		// log.info("Adding edge dependency to sorter: ", edge.from, " -> ", edge.to)
		ok := ts.add_dependency(&sorter, edge.to, edge.from)
		assert(ok, "Failed to add edge dependency to sorter")
	}

	nodes_sorted, cycled := ts.sort(&sorter)

	assert(len(cycled) == 0, "Graph contains cycles")

	layers := make([dynamic][dynamic]NodeHandle, hm.num_used(graph.nodes))

	y_max: i32 = 0
	for node_handle in nodes_sorted {
		max_prev: i32 = 0
		for pre_node_handle in graph_predecessors_of(graph, node_handle) {
			pred_node := hm.get(&graph.nodes, pre_node_handle)
			if pred_node.position.y + 1 > max_prev {
				max_prev = pred_node.position.y + 1
			}
		}

		node := hm.get(&graph.nodes, node_handle)
		node.position.y = max_prev
		if max_prev > y_max {
			y_max = max_prev
		}

		layer := layers[node.position.y]
		append(&layer, node_handle)
		layers[node.position.y] = layer
	}

	// Sort layers so that calculation is stable,
	// topological sort uses maps which cant be stable
	// even with resetting random generator seed
	{
		for layer in layers {
			slice.sort_by(layer[:], proc(a, b: NodeHandle) -> bool {
				return a.idx < b.idx
			})
		}
	}

	// Fill x positions
	if GRAPH_X_ALGORITHM == "naive" {
		// Barycenter algorithm: calculate barycenter for each node and place them accordingly
		for layer in layers {
			if len(layer) == 0 {
				continue // skip empty layers
			}
			// fmt.println("Layer: ", layer)
			for node_handle, i in layer {
				node := hm.get(&graph.nodes, node_handle)
				node.position.x = i32(i)
			}
		}
	} else if GRAPH_X_ALGORITHM == "barycenter" {
		for i in 0 ..= 10 {
			for layer in layers {
				if i % 2 == 0 {
					graph_unwind_crossings(graph, layer[:], true)
				} else {
					graph_unwind_crossings(graph, layer[:], false)
				}
			}
		}
	} else {
		panic("Unknown GRAPH_X_ALGORITHM: " + GRAPH_X_ALGORITHM)
	}

	x_max: i32 = 0
	node_iter = hm.make_iter(&graph.nodes)
	for node in hm.iter(&node_iter) {
		if node.position.x > x_max {
			x_max = node.position.x
		}
	}

	graph.gutters_vertical = make([dynamic]Gutter, x_max + 2)
	graph.gutters_horizontal = make([dynamic]Gutter, y_max + 2)

	// Calculate gutters sizes
	{
		edges_iter := hm.make_iter(&graph.edges)
		for edge in hm.iter(&edges_iter) {
			from_node := hm.get(&graph.nodes, edge.from)
			to_node := hm.get(&graph.nodes, edge.to)

			if from_node.position.y + 1 == to_node.position.y &&
			   from_node.position.x == to_node.position.x {
				continue // Skip edges that are direct vertical connections
			}

			// Horizontal
			{
				horizontal := from_node.position.y + 1
				horizontal_edges := &graph.gutters_horizontal[horizontal].edges
				append(horizontal_edges, edge.handle)
			}

			// Vertical
			{
				if from_node.position.y + 1 == to_node.position.y &&
				   from_node.position.x == to_node.position.x {
					continue // dont use vertical gutter if the edges are on adjecent rows
				}

				vertical_gutter_idx: int
				if from_node.position.x == to_node.position.x {
					vertical_gutter_idx = int(from_node.position.x)
				} else if from_node.position.x < to_node.position.x {
					vertical_gutter_idx = int(to_node.position.x)
				} else {
					vertical_gutter_idx = int(to_node.position.x + 1)
				}

				vertical_edges := &graph.gutters_vertical[vertical_gutter_idx].edges
				append(vertical_edges, edge.handle)
			}
		}

		for &gutter in graph.gutters_vertical {
			gutter.size_px = 2 * gutter_padding + gutter_edge_distance * f32(len(gutter.edges))
		}

		for &gutter in graph.gutters_horizontal {
			gutter.size_px = 2 * gutter_padding + gutter_edge_distance * f32(len(gutter.edges))
		}
	}

	// Fill gutter positions
	{
		previous_width: f32 = 0
		for &gutter in graph.gutters_vertical {
			gutter.pos = previous_width
			previous_width += gutter.size_px + graph.node_size.x
		}

		previous_height: f32 = 0
		for &gutter in graph.gutters_horizontal {
			gutter.pos = previous_height
			previous_height += gutter.size_px + graph.node_size.y
		}

		graph_size = {previous_width, previous_height}
	}

	// Fill node positions
	node_iter = hm.make_iter(&graph.nodes)
	for node in hm.iter(&node_iter) {
		node.position_px = graph_get_node_position_px(graph, node.position)
	}

	// graph_print_gutter(graph)

	// Fill edge segments
	{
		edges_iter := hm.make_iter(&graph.edges)
		for edge in hm.iter(&edges_iter) {
			from_node := hm.get(&graph.nodes, edge.from)
			to_node := hm.get(&graph.nodes, edge.to)

			// middle of from_node
			edge.segments[0] = from_node.position_px + 0.5 * graph.node_size

			if from_node.position.y + 1 == to_node.position.y &&
			   from_node.position.x == to_node.position.x {
				// upper edge of to_node 
				edge.segments[1] = to_node.position_px + (0.5 * {graph.node_size.x, 0})
				edge.arrow_direction = .Down
				continue
			}

			horizontal_gutter := graph.gutters_horizontal[from_node.position.y + 1]
			horizontal_lane := graph_horizontal_lane_for_edge(graph, &horizontal_gutter, edge)

			// horizontal gutter entrance
			edge.segments[1] = {
				edge.segments[0].x,
				horizontal_gutter.pos +
				gutter_padding +
				f32(horizontal_lane) * gutter_edge_distance,
			}

			vertical_gutter_idx: int
			if from_node.position.x == to_node.position.x {
				vertical_gutter_idx = int(from_node.position.x)
			} else if from_node.position.x < to_node.position.x {
				vertical_gutter_idx = int(to_node.position.x)
			} else {
				vertical_gutter_idx = int(to_node.position.x + 1)
			}

			vertical_gutter := graph.gutters_vertical[vertical_gutter_idx]
			vertical_lane := graph_vertical_lane_for_edge(graph, &vertical_gutter, edge)

			// gutter crossing
			edge.segments[2] = {
				vertical_gutter.pos + gutter_padding + f32(vertical_lane) * gutter_edge_distance,
				edge.segments[1].y,
			}

			// vertical gutter exit
			edge.segments[3] = {
				edge.segments[2].x,
				to_node.position_px.y + 0.5 * graph.node_size.y,
			}

			// target edge
			if edge.segments[3].x < to_node.position_px.x {
				edge.segments[4] = {to_node.position_px.x, edge.segments[3].y}
				edge.arrow_direction = .Right
			} else {
				edge.segments[4] = {to_node.position_px.x + graph.node_size.x, edge.segments[3].y}
				edge.arrow_direction = .Left
			}
		}
	}

	return graph_size
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

graph_unwind_crossings :: proc(graph: ^Graph, layer: []NodeHandle, descending: bool) {
	center_struct :: struct {
		handle: NodeHandle,
		center: f32,
		pos:    f32,
	}
	centers := make([]center_struct, len(layer))

	loop := proc(graph: ^Graph, node_handle: NodeHandle, idx: int, centers: []center_struct) {
		node := hm.get(&graph.nodes, node_handle)
		center := graph_calculate_nodes_barycenter(graph, node)
		centers[idx] = center_struct {
			handle = node_handle,
			center = center,
			pos    = f32(idx),
		}
	}

	if descending {
		for node_handle, idx in layer {
			loop(graph, node_handle, idx, centers)
		}
	} else {
		for i := len(layer) - 1; i >= 0; i -= 1 {
			loop(graph, layer[i], i, centers)
		}
	}

	slice.sort_by(
		centers,
		proc(a, b: center_struct) -> bool {
			if a.center == -1 && b.center == -1 {
				return a.pos < b.pos // both have no center, sort by position
			}

			if a.center == -1 {
				// make b go towards its center
				direction := b.pos - b.center
				if direction < 0 {
					return true // b should go left
				} else {
					return false // b should go right
				}
			}
			if b.center == -1 {
				direction := a.pos - a.center
				if direction < 0 {
					return false // a should go right
				} else {
					return true // a should go left
				}
			}
			return a.center < b.center
		},
	)
	for center, i in centers {
		node := hm.get(&graph.nodes, center.handle)
		node.position.x = i32(i)
	}
}

graph_get_node_position_px :: proc(graph: ^Graph, node_pos: V2i) -> V2 {
	// Width:
	width: f32 = 0.0
	for gutter, i in graph.gutters_vertical {
		if i32(i) == node_pos.x {
			width += gutter.size_px
			break
		}
		width += gutter.size_px + graph.node_size.x
	}

	height: f32 = 0.0
	for gutter, i in graph.gutters_horizontal {
		if i32(i) == node_pos.y {
			height += gutter.size_px
			break
		}
		height += gutter.size_px + graph.node_size.y
	}
	return {width, height}
}

graph_horizontal_lane_for_edge :: proc(graph: ^Graph, gutter: ^Gutter, edge: ^Edge) -> i32 {
	for edgeHandle, i in gutter.edges {
		edge_gutter := hm.get(&graph.edges, edgeHandle)
		if edge_gutter.from == edge.from {
			return i32(i)
		}
	}
	panic("Edge not found in gutter")
}

graph_vertical_lane_for_edge :: proc(graph: ^Graph, gutter: ^Gutter, edge: ^Edge) -> i32 {
	for edgeHandle, i in gutter.edges {
		edge_gutter := hm.get(&graph.edges, edgeHandle)
		if edge_gutter.to == edge.to {
			return i32(i)
		}
	}
	panic("Edge not found in gutter")
}

graph_calculate_nodes_barycenter :: proc(graph: ^Graph, node: ^Node) -> f32 {
	sum: f32 = 0
	preds := graph_predecessors_of(graph, node.handle)
	for pred in preds {
		pred_node := hm.get(&graph.nodes, pred)
		sum += f32(pred_node.position.x)
	}

	if len(preds) == 0 {
		return -1
	}
	return sum / f32(len(preds))
}

id :: proc(external_id: $T) -> ExternalID {
	return transmute(ExternalID)external_id
}
