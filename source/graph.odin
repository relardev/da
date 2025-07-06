package game

import clay "clay-odin"
import ts "core:container/topological_sort"
import "core:log"
import "core:slice"
import hm "handle_map"

gutter_edge_distance: f32 = 10.0 // distance between edges in gutters
gutter_padding: f32 = 40.0 // padding around gutters

Graph :: struct {
	nodes:              hm.Handle_Map(Node, NodeHandle, 1024),
	edges:              hm.Handle_Map(Edge, EdgeHandle, 1024),
	draw_gutters:       bool,
	draw_nodes:         bool,
	gutters_vertical:   [dynamic]Gutter,
	gutters_horizontal: [dynamic]Gutter,
	cell_size_px:       Vec2,
}

NodeHandle :: hm.Handle
EdgeHandle :: hm.Handle

Node :: struct {
	handle:      NodeHandle,
	text:        string,
	position:    Vec2i,
	position_px: Vec2,
	size_px:     Vec2,
	depth:       i32,
	clay_id:     clay.ElementId,
}

down: i32 = 1
left: i32 = 2
right: i32 = 3

Edge :: struct {
	handle:          EdgeHandle,
	from:            NodeHandle,
	to:              NodeHandle,
	segments:        [5]Vec2, // points in pixels
	arrow_direction: i32,
}

Gutter :: struct {
	edges:   [dynamic]EdgeHandle,
	pos:     f32,
	size_px: f32,
}

graph_calculate_layout :: proc(graph: ^Graph) {
	sorter: ts.Sorter(NodeHandle)
	main_allocator := context.allocator
	context.allocator = context.temp_allocator
	ts.init(&sorter)
	defer ts.destroy(&sorter)

	node_iter := hm.make_iter(&graph.nodes)
	for node in hm.iter(&node_iter) {
		ok := ts.add_key(&sorter, node.handle)
		assert(ok, "Failed to add node to sorter")
	}

	edge_iter := hm.make_iter(&graph.edges)
	for edge in hm.iter(&edge_iter) {
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

	for i in 0 ..= 10 {
		for layer in layers {
			if i % 2 == 0 {
				graph_unwind_crossings(graph, layer[:], true)
			} else {
				graph_unwind_crossings(graph, layer[:], false)
			}
		}
	}

	x_max: i32 = 0
	node_iter = hm.make_iter(&graph.nodes)
	for node in hm.iter(&node_iter) {
		if node.position.x > x_max {
			x_max = node.position.x
		}
	}
	graph.gutters_vertical = make([dynamic]Gutter, x_max + 2, allocator = main_allocator)
	graph.gutters_horizontal = make([dynamic]Gutter, y_max + 2, allocator = main_allocator)

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

	// Fill cell sizes
	node_iter = hm.make_iter(&graph.nodes)
	for node in hm.iter(&node_iter) {
		if graph.cell_size_px.x < node.size_px.x {
			graph.cell_size_px.x = node.size_px.x
		}
		if graph.cell_size_px.y < node.size_px.y {
			graph.cell_size_px.y = node.size_px.y
		}
	}

	// Fill gutter positions
	{
		previous_width: f32 = 0
		for &gutter in graph.gutters_vertical {
			gutter.pos = previous_width
			previous_width += gutter.size_px + graph.cell_size_px.x
		}

		previous_height: f32 = 0
		for &gutter in graph.gutters_horizontal {
			gutter.pos = previous_height
			previous_height += gutter.size_px + graph.cell_size_px.y
		}
	}

	// Fill node positions
	node_iter = hm.make_iter(&graph.nodes)
	for node in hm.iter(&node_iter) {
		node.size_px = graph.cell_size_px
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
			edge.segments[0] = from_node.position_px + 0.5 * from_node.size_px

			if from_node.position.y + 1 == to_node.position.y &&
			   from_node.position.x == to_node.position.x {
				// upper edge of to_node 
				edge.segments[1] = to_node.position_px + (0.5 * {to_node.size_px.x, 0})
				edge.arrow_direction = down
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
				to_node.position_px.y + 0.5 * to_node.size_px.y,
			}

			// target edge
			if edge.segments[3].x < to_node.position_px.x {
				edge.segments[4] = {to_node.position_px.x, edge.segments[3].y}
				edge.arrow_direction = right
			} else {
				edge.segments[4] = {to_node.position_px.x + to_node.size_px.x, edge.segments[3].y}
				edge.arrow_direction = left
			}
		}
	}
}

graph_unwind_crossings :: proc(graph: ^Graph, layer: []NodeHandle, descending: bool) {
	center_struct :: struct {
		handle: NodeHandle,
		center: f32,
		pos:    f32,
	}
	centers := make([]center_struct, len(layer), allocator = context.temp_allocator)

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
				direnction := b.pos - b.center
				if direnction < 0 {
					return true // b should go left
				} else {
					return false // b should go right
				}
			}
			if b.center == -1 {
				direnction := a.pos - a.center
				if direnction < 0 {
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

graph_get_node_position_px :: proc(graph: ^Graph, node_pos: Vec2i) -> Vec2 {
	// Width:
	width: f32 = 0.0
	for gutter, i in graph.gutters_vertical {
		if i32(i) == node_pos.x {
			width += gutter.size_px
			break
		}
		width += gutter.size_px + graph.cell_size_px.x
	}

	height: f32 = 0.0
	for gutter, i in graph.gutters_horizontal {
		if i32(i) == node_pos.y {
			height += gutter.size_px
			break
		}
		height += gutter.size_px + graph.cell_size_px.y
	}
	return {width, height}
}

graph_predecessors_of :: proc(
	graph: ^Graph,
	node: NodeHandle,
	allocator := context.allocator,
) -> []NodeHandle {
	edges_iter := hm.make_iter(&graph.edges)
	preds := make([dynamic]NodeHandle, 0, 16, allocator = allocator)
	for edge in hm.iter(&edges_iter) {
		if edge.to == node {
			append(&preds, edge.from)
		}
	}
	return preds[:]
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

graph_close :: proc(graph: ^Graph) {
	for gutter in graph.gutters_vertical {
		delete(gutter.edges)
	}
	delete(graph.gutters_vertical)

	for gutter in graph.gutters_horizontal {
		delete(gutter.edges)
	}
	delete(graph.gutters_horizontal)
}

graph_print_gutter :: proc(graph: ^Graph) {
	log.info("Vertical Gutters:")
	for gutter, i in graph.gutters_vertical {
		for edge_handle in gutter.edges {
			edge := hm.get(&graph.edges, edge_handle)
			from_node := hm.get(&graph.nodes, edge.from)
			to_node := hm.get(&graph.nodes, edge.to)
			log.info(i, edge_handle, from_node.text, "->", to_node.text)
		}
	}

	log.info("Horizontal Gutters:")
	for gutter, i in graph.gutters_horizontal {
		for edge_handle in gutter.edges {
			edge := hm.get(&graph.edges, edge_handle)
			from_node := hm.get(&graph.nodes, edge.from)
			to_node := hm.get(&graph.nodes, edge.to)
			log.info(i, edge_handle, from_node.text, "->", to_node.text)
		}
	}

}
