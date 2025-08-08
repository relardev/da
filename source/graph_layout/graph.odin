package graph_layout

import "base:runtime"
import ts "core:container/topological_sort"
import "core:mem"
import "core:slice"

gutter_edge_distance :: 10.0 // distance between edges in gutters
gutter_padding :: 40.0 // padding around gutters

GRAPH_X_ALGORITHM :: "naive" // "naive"

V2 :: [2]f32
V2i :: [2]i32

Graph :: struct {
	allocator:          mem.Allocator,
	nodes:              [dynamic]Node,
	edges:              [dynamic]Edge,
	gutters_vertical:   [dynamic]Gutter,
	gutters_horizontal: [dynamic]Gutter,
	node_size:          V2,
}

NodeOffset :: int

ExternalID :: u64

Node :: struct {
	external_id: ExternalID,
	position:    V2i,
	position_px: V2,
}

EdgeOffset :: int

ArrowDirection :: enum {
	Down,
	Left,
	Right,
}

Edge :: struct {
	from:            NodeOffset,
	to:              NodeOffset,
	segments:        [5]V2,
	arrow_direction: ArrowDirection,
}

Gutter :: struct {
	edges:   [dynamic]EdgeOffset,
	pos:     f32,
	size_px: f32,
}

Layers :: [dynamic][dynamic]NodeOffset

allocation_needed :: proc(nodes: int, edges: int) -> int {
	sum := 0

	// base structures
	{
		sum += size_of(Graph)
		sum += size_of(Node) * nodes
		sum += size_of(Edge) * edges

		gutter_edge_elements_size := size_of(EdgeOffset) * edges

		// each edge will be in at most 1 horizontal and 1 vertical gutter
		sum += 2 * size_of(Gutter) * nodes + gutter_edge_elements_size
	}

	// topological sort
	{
		// topological sort data structures
		single_edge_relations_dependents_size := runtime.map_total_allocation_size(
			1,
			runtime.map_info(map[NodeOffset]struct {}),
		)

		all_edges_in_relations_dependents_size := runtime.map_total_allocation_size(
			uintptr(edges),
			runtime.map_info(map[EdgeOffset]struct {}),
		)

		relations_map_size := runtime.map_total_allocation_size(
			uintptr(nodes),
			runtime.map_info(map[NodeOffset]ts.Relations(NodeOffset)),
		)

		sum +=
			int(single_edge_relations_dependents_size + all_edges_in_relations_dependents_size) +
			int(relations_map_size) +
			size_of(ts.Sorter(NodeOffset))

		// sorting result
		sum += nodes * size_of(NodeOffset)
	}

	// layers
	{
		// outer dynamic array - holding all rows (data ptr + len + cap)
		sum += size_of(Layers)
		// outer dynamic array elements - rows
		sum += size_of([dynamic]NodeOffset) * nodes
		// inner dynamic array - rows values
		sum += size_of(NodeOffset) * nodes
	}

	// predecessors
	sum += size_of([dynamic]NodeOffset) * nodes

	return sum
}

graph_new :: proc(allocator := context.allocator) -> Graph {
	return Graph {
		allocator = allocator,
		nodes = make([dynamic]Node, 0, 1024, allocator = allocator),
		edges = make([dynamic]Edge, 0, 1024, allocator = allocator),
	}
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
	append(&graph.nodes, Node{external_id = external_id})

	if graph.node_size.x < size.x {
		graph.node_size.x = size.x
	}

	if graph.node_size.y < size.y {
		graph.node_size.y = size.y
	}
}

graph_add_edge :: proc(graph: ^Graph, from: ExternalID, to: ExternalID) -> bool {
	// find from offset
	from_offset: NodeOffset
	FIND_FROM: {
		for &node, i in graph.nodes {
			if node.external_id == from {
				from_offset = i
				break FIND_FROM
			}
		}

		return false
	}


	// find to offset
	to_offset: NodeOffset
	FIND_TO: {
		for &node, i in graph.nodes {
			if node.external_id == to {
				to_offset = i
				break FIND_TO
			}
		}

		return false
	}

	if from_offset == to_offset {
		return false // self-loop, not allowed
	}

	append(&graph.edges, Edge{from = from_offset, to = to_offset})
	return true
}

graph_read_node :: proc(graph: ^Graph, external_id: ExternalID) -> (V2, bool) {
	for &node in graph.nodes {
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
	// find from offset
	from_offset: NodeOffset
	FIND_FROM: {
		for &node, i in graph.nodes {
			if node.external_id == from {
				from_offset = i
				break FIND_FROM
			}
		}

		return {}, false
	}

	// find to offset
	to_offset: NodeOffset
	FIND_TO: {
		for &node, i in graph.nodes {
			if node.external_id == to {
				to_offset = i
				break FIND_TO
			}
		}

		return {}, false
	}

	for &edge in graph.edges {
		if edge.from == from_offset && edge.to == to_offset {
			return EdgeResult{segments = edge.segments[:], arrow_direction = edge.arrow_direction},
				true
		}
	}

	return {}, false // edge not found
}

graph_calculate_layout :: proc(graph: ^Graph) -> (graph_size: V2, ok: bool) {
	sorter: ts.Sorter(NodeOffset)
	context.allocator = graph.allocator

	ts.init(&sorter)
	defer ts.destroy(&sorter)

	for _, i in graph.nodes {
		// log.info("Adding node to sorter: ", node.offset, " - ", node.name)
		ok = ts.add_key(&sorter, i)
		if !ok {
			return {}, false
		}
	}

	for &edge in graph.edges {
		// log.info("Adding edge dependency to sorter: ", edge.from, " -> ", edge.to)
		ok = ts.add_dependency(&sorter, edge.to, edge.from)
		if !ok {
			return {}, false
		}
	}

	nodes_sorted, cycled := ts.sort(&sorter)

	if len(cycled) != 0 {
		return {}, false
	}

	layers := make(Layers, len(graph.nodes))

	y_max: i32 = 0
	predecessor_list := make([dynamic]NodeOffset, 0, len(graph.nodes), allocator = graph.allocator)
	for node_offset in nodes_sorted {
		max_prev: i32 = 0
		graph_fill_predecessors_of(graph, node_offset, &predecessor_list)
		for pre_node_offset in predecessor_list {
			pred_node := graph.nodes[pre_node_offset]
			if pred_node.position.y + 1 > max_prev {
				max_prev = pred_node.position.y + 1
			}
		}

		node := &graph.nodes[node_offset]
		node.position.y = max_prev
		if max_prev > y_max {
			y_max = max_prev
		}

		layer := layers[node.position.y]
		append(&layer, node_offset)
		layers[node.position.y] = layer
	}

	// Sort layers so that calculation is stable,
	// topological sort uses maps which cant be stable
	// even with resetting random generator seed
	{
		for layer in layers {
			slice.sort_by(layer[:], proc(a, b: NodeOffset) -> bool {
				return a < b
			})
		}
	}

	// Fill x positions
	if GRAPH_X_ALGORITHM == "naive" {
		for layer in layers {
			if len(layer) == 0 {
				continue // skip empty layers
			}
			// fmt.println("Layer: ", layer)
			for node_offset, i in layer {
				node := &graph.nodes[node_offset]
				node.position.x = i32(i)
			}
		}
	} else {
		panic("Unknown GRAPH_X_ALGORITHM: " + GRAPH_X_ALGORITHM)
	}

	x_max: i32 = 0
	for &node in graph.nodes {
		if node.position.x > x_max {
			x_max = node.position.x
		}
	}

	graph.gutters_vertical = make([dynamic]Gutter, x_max + 2)
	graph.gutters_horizontal = make([dynamic]Gutter, y_max + 2)

	// Calculate gutters sizes
	{
		for &edge, i in graph.edges {
			from_node := graph.nodes[edge.from]
			to_node := graph.nodes[edge.to]

			if from_node.position.y + 1 == to_node.position.y &&
			   from_node.position.x == to_node.position.x {
				continue // Skip edges that are direct vertical connections
			}

			// Horizontal
			{
				horizontal := from_node.position.y + 1
				horizontal_edges := &graph.gutters_horizontal[horizontal].edges
				append(horizontal_edges, i)
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
				append(vertical_edges, i)
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
	for &node in graph.nodes {
		node.position_px = graph_get_node_position_px(graph, node.position)
	}

	// graph_print_gutter(graph)

	// Fill edge segments
	{
		for &edge in graph.edges {
			from_node := graph.nodes[edge.from]
			to_node := graph.nodes[edge.to]

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
			horizontal_lane := graph_horizontal_lane_for_edge(graph, &horizontal_gutter, edge.from)

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
			vertical_lane := graph_vertical_lane_for_edge(graph, &vertical_gutter, edge.to)

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

	return graph_size, true
}

graph_fill_predecessors_of :: proc(
	graph: ^Graph,
	offset: NodeOffset,
	preds: ^[dynamic]NodeOffset,
) {
	clear(preds)
	for &edge in graph.edges {
		if edge.to == offset {
			append(preds, edge.from)
		}
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

graph_horizontal_lane_for_edge :: proc(
	graph: ^Graph,
	gutter: ^Gutter,
	node_offset: NodeOffset,
) -> i32 {
	for offset, i in gutter.edges {
		edge := &graph.edges[offset]
		if edge.from == node_offset {
			return i32(i)
		}
	}
	panic("Edge not found in gutter")
}

graph_vertical_lane_for_edge :: proc(
	graph: ^Graph,
	gutter: ^Gutter,
	node_offset: NodeOffset,
) -> i32 {
	for offset, i in gutter.edges {
		edge := &graph.edges[offset]
		if edge.to == node_offset {
			return i32(i)
		}
	}
	panic("Edge not found in gutter")
}

id :: proc(external_id: $T) -> ExternalID {
	return transmute(ExternalID)external_id
}
