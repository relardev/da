package graph_layout

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:slice"
import ts "topological_sort"

gutter_edge_distance :: 10.0 // distance between edges in gutters
gutter_padding :: 40.0 // padding around gutters

GRAPH_X_ALGORITHM :: "naive" // "naive"

V2 :: [2]f32
V2i :: [2]i32

Graph :: struct {
	arena:              mem.Arena,
	arena_allocator:    mem.Allocator,
	allocator:          mem.Allocator,
	nodes:              [dynamic]Node,
	edges:              [dynamic]Edge,
	gutters_vertical:   [dynamic]Gutter,
	gutters_horizontal: [dynamic]Gutter,
	node_size:          V2,
}

NodeOffset :: u16
EdgeOffset :: u16

ExternalID :: u64

Node :: struct {
	external_id:     ExternalID,
	position:        V2i,
	position_px:     V2,
	number_of_edges: u16,
}

ArrowDirection :: enum u8 {
	Down,
	Left,
	Right,
}

Edge :: struct {
	from:            NodeOffset, // 2 bytes
	to:              NodeOffset, // 2 bytes
	segments:        [5]V2,
	arrow_direction: ArrowDirection,
}

Gutter :: struct {
	edges:   [dynamic]EdgeOffset,
	pos:     f32,
	size_px: f32,
}

Layers :: [dynamic][dynamic]NodeOffset

allocation_needed :: proc(nodes: int, edges: int) -> (size: int, alginment: int) {
	calculate_memory :: proc(sum, new_mem, align: int) -> int {
		reminder := sum % align
		if reminder == 0 {
			return sum + new_mem
		}
		padding := align - (sum % align)
		return sum + padding + new_mem
	}

	when ODIN_DEBUG {
		add_memory :: proc(
			sum, new_mem, align: int,
			name: string,
			loc := #caller_location,
		) -> int {
			result := calculate_memory(sum, new_mem, align)
			log.infof(
				"%d\t%d\t%d\t%d\t%s",
				sum,
				result - new_mem,
				new_mem,
				align,
				name,
				location = loc,
			)
			return result
		}
	} else {
		add_memory :: proc(sum, new_mem, align: int, _: string) -> int {
			return calculate_memory(sum, new_mem, align)
		}
	}

	sum := 0

	// base structures
	{
		sum = add_memory(sum, size_of(Graph), align_of(Graph), "Graph")
		sum = add_memory(
			sum,
			size_of(Node) * nodes,
			align_of(Node),
			fmt.tprintf("Nodes: %d", nodes),
		)
		sum = add_memory(
			sum,
			size_of(Edge) * edges,
			align_of(Edge),
			fmt.tprintf("Edges: %d", edges),
		)

	}

	// topological sort
	{
		sum = add_memory(
			sum,
			int(
				runtime.map_total_allocation_size(
					uintptr(max(nodes, 8)),
					runtime.map_info(map[NodeOffset]ts.Relations(NodeOffset)),
				),
			),
			64,
			"ts, relations map",
		)

		sum = add_memory(
			sum,
			int(runtime.map_total_allocation_size(8, runtime.map_info(map[NodeOffset]bool))) *
			edges,
			64,
			"ts, maps for edges, size 1",
		)

		sum = add_memory(
			sum,
			int(
				runtime.map_total_allocation_size(
					uintptr(max(edges, 8)),
					runtime.map_info(map[EdgeOffset]bool),
				),
			),
			64,
			"ts, maps for edges, size edges",
		)

		sum = add_memory(
			sum,
			nodes * size_of(NodeOffset),
			align_of(NodeOffset),
			"ts, result, sorted nodes",
		)
	}

	// layers
	{
		// outer dynamic array elements - rows
		sum = add_memory(
			sum,
			size_of([dynamic]NodeOffset) * nodes,
			align_of([dynamic]NodeOffset),
			"Layers, rows offsets",
		)

		// inner dynamic array - rows values
		sum = add_memory(
			sum,
			size_of(NodeOffset) * nodes,
			align_of(NodeOffset),
			"Layers, rows values",
		)
	}

	sum = add_memory(
		sum,
		size_of([dynamic]NodeOffset) * nodes,
		align_of([dynamic]NodeOffset),
		"Predecessors",
	)

	gutter_edge_elements_size := size_of(EdgeOffset) * edges
	vertical_or_horizontal_gutter_size := size_of(Gutter) * (nodes + 2)
	// each edge will be in at most 1 horizontal and 1 vertical gutter
	sum = add_memory(sum, vertical_or_horizontal_gutter_size, align_of(Gutter), "Gutters Vertical")

	sum = add_memory(
		sum,
		gutter_edge_elements_size,
		align_of(EdgeOffset),
		"Gutters Vertical Edges",
	)

	sum = add_memory(
		sum,
		vertical_or_horizontal_gutter_size + gutter_edge_elements_size,
		align_of(Gutter),
		"Gutters Horizontal",
	)

	sum = add_memory(
		sum,
		gutter_edge_elements_size,
		align_of(EdgeOffset),
		"Gutters Horizontal Edges",
	)

	return sum, 64
}

graph_new :: proc(buffer: []u8, nodes: int, edges: int) -> ^Graph {
	graph := cast(^Graph)raw_data(buffer)
	size_of_graph := size_of(Graph)
	rest_of_buffer := buffer[size_of_graph:]

	mem.arena_init(&graph.arena, rest_of_buffer)
	graph.arena_allocator = mem.arena_allocator(&graph.arena)
	when ODIN_DEBUG {
		graph.allocator = print_allocator(&graph.arena_allocator)
	} else {
		graph.allocator = graph.arena_allocator
	}

	graph.nodes = make([dynamic]Node, 0, nodes, allocator = graph.allocator)
	graph.nodes.allocator = mem.panic_allocator()
	graph.edges = make([dynamic]Edge, 0, edges, allocator = graph.allocator)
	graph.edges.allocator = mem.panic_allocator()

	mark_memory_used(graph, graph, "Graph")
	mark_memory_used(graph, raw_data(graph.nodes), "Nodes")
	mark_memory_used(graph, raw_data(graph.edges), "Edges")
	return graph
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
				from_offset = NodeOffset(i)
				node.number_of_edges += 1
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
				to_offset = NodeOffset(i)
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
				from_offset = NodeOffset(i)
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
				to_offset = NodeOffset(i)
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

	ts.init(&sorter, len(graph.nodes))

	sorter.relations.allocator = mem.panic_allocator()
	mark_memory_used(
		graph,
		rawptr(runtime.map_data(transmute(runtime.Raw_Map)sorter.relations)),
		"ts, relations map",
	)

	for node, i in graph.nodes {
		// log.info("Adding node to sorter: ", node.offset, " - ", node.name)
		ts.add_key(&sorter, NodeOffset(i), int(node.number_of_edges))
	}

	for &edge in graph.edges {
		// log.info("Adding edge dependency to sorter: ", edge.from, " -> ", edge.to)
		ok = ts.add_dependency(&sorter, edge.to, edge.from)
		if !ok {
			return {}, false
		}
	}

	nodes_sorted, cycled := ts.sort(&sorter, result_allocator = graph.allocator)

	mark_memory_used(graph, raw_data(nodes_sorted), "ts, result, sorted nodes")

	if cycled {
		return {}, false
	}

	layers := make(Layers, len(graph.nodes), allocator = graph.allocator)

	y_max: i32 = 0
	predecessor_list := make([dynamic]NodeOffset, 0, len(graph.nodes), allocator = graph.allocator)
	mark_memory_used(graph, raw_data(predecessor_list), "Predecessors")
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

	graph.gutters_vertical = make([dynamic]Gutter, x_max + 2, allocator = graph.allocator)
	mark_memory_used(graph, raw_data(graph.gutters_vertical), "Gutters, vertical")
	graph.gutters_horizontal = make([dynamic]Gutter, y_max + 2, allocator = graph.allocator)
	mark_memory_used(graph, raw_data(graph.gutters_horizontal), "Gutters, horizontal")

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
				append(horizontal_edges, EdgeOffset(i))
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
				append(vertical_edges, EdgeOffset(i))
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

@(private = "file")
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

@(private = "file")
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

@(private = "file")
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

@(private = "file")
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

@(private = "file")
mark_memory_used :: proc(
	graph: ^Graph,
	object_start: rawptr,
	name: string,
	loc := #caller_location,
) {
	when ODIN_DEBUG {
		log.infof("%d - %s", uintptr(object_start) - uintptr(graph), name, location = loc)
	}
}
