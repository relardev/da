package graph_layout

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:slice"
import ts "topological_sort"

_ :: log

gutter_edge_distance :: 20.0 // distance between edges in gutters
gutter_padding :: 40.0 // padding around gutters
node_landing_padding :: 10.0 // padding for node side where edge arrows can "land"
bridge_gap :: 5.0 // gap size for edge crossings, whole gap will be 2*bridge_gap

max_segments_per_edge :: 256

// GRAPH_X_ALGORITHM :: "naive"
GRAPH_X_ALGORITHM :: "barycenter"

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
	barycenter_x:    f32,
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
	// TODO use small array
	segments:        [max_segments_per_edge]Segment,
	arrow_direction: ArrowDirection,
}

Gutter :: struct {
	edges:   [dynamic]EdgeOffset,
	pos:     f32,
	size_px: f32,
}

LayerCell :: struct {
	node_offset: NodeOffset,
	x:           f32,
}

Layers :: [dynamic][dynamic]LayerCell

allocation_needed :: proc(
	nodes: int,
	edges: int,
) -> (
	size: int,
	alginment: int,
) {

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
			size_of(Node) * (nodes + 1), // +1 for the no-node offset
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
			int(
				runtime.map_total_allocation_size(
					8,
					runtime.map_info(map[NodeOffset]bool),
				),
			) *
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
			size_of([dynamic]LayerCell) * nodes,
			align_of([dynamic]LayerCell),
			"Layers, rows offsets",
		)

		// inner dynamic array - rows values
		sum = add_memory(
			sum,
			size_of(LayerCell) * nodes,
			align_of(LayerCell),
			"Layers, rows values",
		)
	}

	sum = add_memory(
		sum,
		size_of([dynamic]NodeOffset) * nodes,
		align_of([dynamic]NodeOffset),
		"Predecessors",
	)

	// X algorithm
	{
		switch GRAPH_X_ALGORITHM {
		case "naive":
		// nothing to do, no additional memory needed
		case "barycenter":
			// predecessors list for each node
			bytes, align := optimal_assign_quadratic_allocation_needed(nodes)
			sum = add_memory(sum, bytes, align, "optimal_assign_quadratic")
		case:
			panic("Unknown GRAPH_X_ALGORITHM: " + GRAPH_X_ALGORITHM)
		}
	}

	gutter_edge_elements_size := size_of(EdgeOffset) * edges
	vertical_or_horizontal_gutter_size := size_of(Gutter) * (nodes + 2)
	// each edge will be in at most 1 horizontal and 1 vertical gutter
	sum = add_memory(
		sum,
		vertical_or_horizontal_gutter_size,
		align_of(Gutter),
		"Gutters Vertical",
	)

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

	sum = add_memory(
		sum,
		int(
			runtime.map_total_allocation_size(
				uintptr(max(nodes - 1, 8)),
				runtime.map_info(map[NodeOffset]bool),
			),
		),
		64,
		"incomming nodes set",
	)

	sum = add_memory(
		sum,
		size_of([dynamic]NodeOffset) * (nodes - 1),
		align_of(NodeOffset),
		"incomming nodes array",
	)

	return sum, 64
}

graph_new :: proc(buffer: []u8, nodes: int, edges: int) -> ^Graph {
	graph := cast(^Graph)raw_data(buffer)
	mark_memory_used(graph, graph, "Graph")
	size_of_graph := size_of(Graph)
	rest_of_buffer := buffer[size_of_graph:]

	mem.arena_init(&graph.arena, rest_of_buffer)
	graph.arena_allocator = mem.arena_allocator(&graph.arena)
	when ODIN_DEBUG {
		graph.allocator = print_allocator(&graph.arena_allocator)
		// graph.allocator = graph.arena_allocator
	} else {
		graph.allocator = graph.arena_allocator
	}

	graph.nodes = make(
		[dynamic]Node,
		0,
		nodes + 1,
		allocator = graph.allocator,
	)
	append(&graph.nodes, Node{})

	graph.nodes.allocator = mem.panic_allocator()
	mark_memory_used(graph, raw_data(graph.nodes), "Nodes")

	graph.edges = make([dynamic]Edge, 0, edges, allocator = graph.allocator)
	graph.edges.allocator = mem.panic_allocator()
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

graph_add_edge :: proc(
	graph: ^Graph,
	from: ExternalID,
	to: ExternalID,
) -> bool {
	// find from offset
	from_offset: NodeOffset
	FIND_FROM: {
		for &node, i in graph.nodes {
			if i == 0 {
				continue
			}
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
			if i == 0 {
				continue
			}
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
	for &node in graph.nodes[1:] {
		if node.external_id == external_id {
			return node.position_px, true
		}
	}
	return {}, false
}

EdgeResult :: struct {
	start:           V2,
	segments:        []Segment,
	arrow_direction: ArrowDirection,
}

SegmentType :: enum u8 {
	Point,
	Bridge,
}

Segment :: struct {
	type: SegmentType,
	end:  V2,
}

graph_read_edge :: proc(
	graph: ^Graph,
	from: ExternalID,
	to: ExternalID,
) -> (
	EdgeResult,
	bool,
) {
	// find from offset
	from_offset: NodeOffset
	FIND_FROM: {
		for &node, i in graph.nodes {
			if i == 0 {
				continue
			}
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
			if i == 0 {
				continue
			}
			if node.external_id == to {
				to_offset = NodeOffset(i)
				break FIND_TO
			}
		}

		return {}, false
	}

	for &edge in graph.edges {
		if edge.from == from_offset && edge.to == to_offset {
			first_zero := max_segments_per_edge
			for segment, i in edge.segments {
				if segment == {} {
					first_zero = i
					break
				}
			}
			return EdgeResult {
					segments = edge.segments[:first_zero],
					arrow_direction = edge.arrow_direction,
				},
				true
		}
	}

	return {}, false // edge not found
}

graph_calculate_layout :: proc(graph: ^Graph) -> (graph_size: V2, ok: bool) {
	sorter: ts.Sorter(NodeOffset)
	context.allocator = graph.allocator

	nodes_count := len(graph.nodes) - 1

	ts.init(&sorter, nodes_count)

	sorter.relations.allocator = mem.panic_allocator()
	mark_memory_used(
		graph,
		rawptr(runtime.map_data(transmute(runtime.Raw_Map)sorter.relations)),
		"ts, relations map",
	)

	for node, i in graph.nodes {
		if i == 0 { 	// skip zero-node
			continue
		}
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

	nodes_sorted, cycled := ts.sort(
		&sorter,
		result_allocator = graph.allocator,
	)

	mark_memory_used(graph, raw_data(nodes_sorted), "ts, result, sorted nodes")

	if cycled {
		return {}, false
	}

	layers := make(Layers, nodes_count, allocator = graph.allocator)
	mark_memory_used(graph, raw_data(layers), "Layers")

	y_max: i32 = 0

	predecessor_list := make(
		[dynamic]NodeOffset,
		0,
		nodes_count,
		allocator = graph.allocator,
	)
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
		x := f32(len(layer))
		append(&layer, LayerCell{node_offset = node_offset, x = x})
		layers[node.position.y] = layer
		node.barycenter_x = x
	}

	// Sort layers so that calculation is stable,
	// topological sort uses maps which cant be stable
	// even with resetting random generator seed
	{
		for layer in layers {
			slice.sort_by(layer[:], proc(a, b: LayerCell) -> bool {
				return a.node_offset < b.node_offset
			})
		}
	}

	for &layer in layers {
		endOffset := len(layer)
		non_zero_resize(&layer, cap(layer))
		for &cell in layer[endOffset:] {
			cell.x = -1
		}
	}

	// fmt.println("Layers after initial pass:", layers)

	// Fill x positions
	switch GRAPH_X_ALGORITHM {
	case "naive":
	// do nothing, the x positions will be filled with layer append order
	case "barycenter":
		for i in 0 ..< 10 {
			direction := i % 2
			// fmt.println(
			// 	"Barycenter iteration: ",
			// 	i,
			// 	", direction: ",
			// 	direction,
			// )
			LAYERING: for layer in layers {
				if len(layer) == 0 {
					break LAYERING
				}
				for &cell in layer {
					if cell.node_offset == 0 {
						continue
					}
					if direction == 0 {
						graph_fill_predecessors_of(
							graph,
							cell.node_offset,
							&predecessor_list,
						)
					} else {
						graph_fill_children_of(
							graph,
							cell.node_offset,
							&predecessor_list,
						)
					}

					sum: f32 = 0
					for pred in predecessor_list {
						sum += f32(graph.nodes[pred].barycenter_x)
					}
					node := &graph.nodes[cell.node_offset]

					if len(predecessor_list) != 0 {
						cell.x = sum / f32(len(predecessor_list))
						node.barycenter_x = cell.x
					}
				}

				slice.sort_by(
					layer[:],
					proc(a, b: LayerCell) -> bool {
						if a.x == b.x {
							return a.node_offset < b.node_offset // stable sort
						}
						return a.x < b.x
					},
				)

				arena_usage := graph.arena.offset
				optimal_assign_quadratic(layer[:], allocator = graph.allocator)

				graph.arena.offset = arena_usage

				for &cell, j in layer {
					node := &graph.nodes[cell.node_offset]
					node.barycenter_x = f32(j)
				}
			}
		}
	case:
		panic("Unknown GRAPH_X_ALGORITHM: " + GRAPH_X_ALGORITHM)
	}

	for layer in layers {
		if len(layer) == 0 {
			continue // skip empty layers
		}
		// fmt.println("Layer: ", layer)
		for cell, i in layer {
			if cell.node_offset == 0 {
				continue
			}
			node := &graph.nodes[cell.node_offset]
			node.position.x = i32(i)
		}
	}

	x_max: i32 = 0
	for &node in graph.nodes {
		if node.position.x > x_max {
			x_max = node.position.x
		}
	}

	graph.gutters_vertical = make(
		[dynamic]Gutter,
		x_max + 2,
		allocator = graph.allocator,
	)
	mark_memory_used(
		graph,
		raw_data(graph.gutters_vertical),
		"Gutters, vertical",
	)
	graph.gutters_horizontal = make(
		[dynamic]Gutter,
		y_max + 2,
		allocator = graph.allocator,
	)
	mark_memory_used(
		graph,
		raw_data(graph.gutters_horizontal),
		"Gutters, horizontal",
	)

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
				horizontal_gutter_idx := from_node.position.y + 1
				horizontal_edges := &graph.gutters_horizontal[horizontal_gutter_idx].edges
				found := false
				for horizontal_edge_idx in horizontal_edges {
					horizontal_edge := &graph.edges[horizontal_edge_idx]
					if horizontal_edge.from == edge.from {
						found = true
						break
					}
				}
				if !found {
					append(horizontal_edges, EdgeOffset(i))
				}
			}

			// Vertical
			{
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

		// Sort vertical gutters to have left arrows on the left and right on the right
		for gutter, gutter_x in graph.gutters_vertical {
			i := 0
			length := len(gutter.edges)
			if length <= 0 {
				continue
			}
			j := length - 1
			look_for_left := true
			look_for_right := true
			for i < j {
				if look_for_left {
					edge := &graph.edges[gutter.edges[i]]
					node := graph.nodes[edge.to]
					if node.position.x >= i32(gutter_x) {
						look_for_left = false
					} else {
						i += 1
					}
				}
				if look_for_right {
					edge := &graph.edges[gutter.edges[j]]
					node := graph.nodes[edge.to]
					if node.position.x < i32(gutter_x) {
						look_for_right = false
					} else {
						j -= 1
					}
				}

				if !look_for_left && !look_for_right {
					gutter.edges[i], gutter.edges[j] =
						gutter.edges[j], gutter.edges[i]
					look_for_left = true
					look_for_right = true
					i += 1
					j -= 1
				}
			}
		}

		for &gutter in graph.gutters_vertical {
			gutter.size_px =
				2 * gutter_padding +
				gutter_edge_distance * f32(len(gutter.edges))
		}

		for &gutter in graph.gutters_horizontal {
			gutter.size_px =
				2 * gutter_padding +
				gutter_edge_distance * f32(len(gutter.edges))
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
	for &node in graph.nodes[1:] {
		node.position_px = graph_get_node_position_px(graph, node.position)
	}

	// graph_print_gutter(graph)

	// Fill edge segments
	{
		// unique nodes that lead to this node via gutter
		incomming_nodes_set := make(
			map[NodeOffset]bool,
			map_capacity(len(graph.nodes) - 1),
			allocator = graph.allocator,
		)

		incomming_nodes_set.allocator = mem.panic_allocator()
		mark_memory_used(
			graph,
			rawptr(
				runtime.map_data(
					transmute(runtime.Raw_Map)incomming_nodes_set,
				),
			),
			"incomming nodes",
		)

		incomming_nodes_array := make(
			[dynamic]NodeOffset,
			0,
			len(graph.nodes) - 1,
			allocator = graph.allocator,
		)
		incomming_nodes_array.allocator = mem.panic_allocator()

		mark_memory_used(
			graph,
			raw_data(incomming_nodes_array),
			"incomming nodes array",
		)

		for &edge in graph.edges {
			from_node := graph.nodes[edge.from]
			to_node := graph.nodes[edge.to]

			// middle of from_node
			edge_segment_0 := from_node.position_px + 0.5 * graph.node_size
			edge.segments[0] = Segment {
				type = .Point,
				end  = edge_segment_0,
			}

			if from_node.position.y + 1 == to_node.position.y &&
			   from_node.position.x == to_node.position.x { 	// direct vertical connection
				edge.segments[1] = Segment {
					type = .Point,
					end  = to_node.position_px + (0.5 * {graph.node_size.x, 0}),
				}
				edge.arrow_direction = .Down
				continue
			}

			horizontal_gutter :=
				graph.gutters_horizontal[from_node.position.y + 1]
			horizontal_lane := graph_horizontal_lane_for_edge(
				graph,
				&horizontal_gutter,
				edge.from,
			)

			edge_segment_1_y :=
				horizontal_gutter.pos +
				gutter_padding +
				f32(horizontal_lane) * gutter_edge_distance
			// horizontal gutter entrance
			edge.segments[1] = Segment {
				type = .Point,
				end  = {edge_segment_0.x, edge_segment_1_y},
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
			vertical_lane := graph_vertical_lane_for_edge(
				graph,
				&vertical_gutter,
				edge.from,
			)

			edge_segment_2_x :=
				vertical_gutter.pos +
				gutter_padding +
				f32(vertical_lane) * gutter_edge_distance
			// gutter crossing
			edge.segments[2] = Segment {
				type = .Point,
				end  = {edge_segment_2_x, edge_segment_1_y},
			}


			sibling_node_offset := sibling(
				graph,
				&to_node,
				edge.to,
				vertical_gutter_idx,
			)

			clear(&incomming_nodes_set)
			clear(&incomming_nodes_array)

			for edge_offset in vertical_gutter.edges {
				edge_in_gutter := &graph.edges[edge_offset]
				if edge_in_gutter.to == edge.to ||
				   edge_in_gutter.to == sibling_node_offset {
					incomming_nodes_set[edge_in_gutter.from] = true
				}
			}

			for node_offset, _ in incomming_nodes_set {
				append(&incomming_nodes_array, node_offset)
			}

			slice.sort(incomming_nodes_array[:])

			percentage: f32 = -1
			for node_offset, i in incomming_nodes_array {
				if node_offset == edge.from {
					percentage =
						(1 + f32(i)) / f32(len(incomming_nodes_array) + 1)
					break
				}
			}
			if percentage == -1 {
				panic("Edge from node not found in incomming nodes set")
			}

			edge_segment_3_x := edge_segment_2_x
			edge_segment_3_y :=
				to_node.position_px.y +
				node_landing_padding +
				percentage * (graph.node_size.y - 2 * node_landing_padding)
			// vertical gutter exit
			edge.segments[3] = Segment {
				type = .Point,
				end  = {edge_segment_3_x, edge_segment_3_y},
			}

			// target edge
			if edge_segment_3_x < to_node.position_px.x {
				edge.segments[4] = Segment {
					type = .Point,
					end  = {to_node.position_px.x, edge_segment_3_y},
				}
				edge.arrow_direction = .Right
			} else {
				edge.segments[4] = Segment {
					type = .Point,
					end  = {
						to_node.position_px.x + graph.node_size.x,
						edge_segment_3_y,
					},
				}
				edge.arrow_direction = .Left
			}
		}

		insertBridge :: proc(
			segments: []Segment,
			idx: int,
			start, end: V2,
		) -> bool {
			if segments[len(segments) - 1] != {} ||
			   segments[len(segments) - 2] != {} {
				return false // no space for bridge
			}

			// create 2 empty spaces for point and bridge
			for i := len(segments) - 1; i - 2 >= idx; i -= 1 {
				segments[i] = segments[i - 2]
			}

			segments[idx] = Segment {
				type = .Point,
				end  = start,
			}

			segments[idx + 1] = Segment {
				type = .Bridge,
				end  = end,
			}

			return true
		}

		isVertical :: proc(start, end: V2) -> bool {return start.x == end.x}
		crossingPoint :: proc(
			a_start, a_end, b_start, b_end: V2,
		) -> (
			V2,
			bool,
		) {
			// Direction vectors
			r := a_end - a_start
			s := b_end - b_start

			// Cross product (r x s)
			cross_rs := r.x * s.y - r.y * s.x

			// Parallel or collinear
			if cross_rs == 0.0 {
				return {0, 0}, false
			}

			// Compute t and u
			diff := b_start - a_start
			t := (diff.x * s.y - diff.y * s.x) / cross_rs
			u := (diff.x * r.y - diff.y * r.x) / cross_rs

			// Check if intersection is within both segments
			if t >= 0.0 && t <= 1.0 && u >= 0.0 && u <= 1.0 {
				intersection := a_start + r * t
				return intersection, true
			}

			return {0, 0}, false
		}

		for &edge_a, edge_a_offset in graph.edges {
			node_a := &graph.nodes[edge_a.from]
			for &edge_b in graph.edges[edge_a_offset + 1:] {
				from_node_b := &graph.nodes[edge_b.from]
				if from_node_b == node_a {
					continue
				}
				for i := 1; i < len(edge_a.segments); i += 1 {
					segment_a := &edge_a.segments[i]
					if segment_a^ == {} {
						break
					}
					prev_segment_a := &edge_a.segments[i - 1]
					for j := 1; j < len(edge_b.segments); j += 1 {
						segment_b := &edge_b.segments[j]
						if segment_b^ == {} {
							break
						}
						prev_segment_b := &edge_b.segments[j - 1]

						cross, didCross := crossingPoint(
							prev_segment_a.end,
							segment_a.end,
							prev_segment_b.end,
							segment_b.end,
						)
						if didCross {
							idx: int
							segments_to_insert_bridge_into: []Segment

							if edge_b.from < edge_a.from {
								idx = i
								i += 2
								segments_to_insert_bridge_into =
								edge_a.segments[:]
							} else {
								idx = j
								j += 2
								segments_to_insert_bridge_into =
								edge_b.segments[:]
							}

							prev := &segments_to_insert_bridge_into[idx - 1]
							next := &segments_to_insert_bridge_into[idx]

							if prev.end == next.end {
								panic("Overlapping segments not supported")
							}

							if next.type == .Bridge {
								continue
							}

							distance := math.sqrt(
								math.pow(prev.end.x - next.end.x, 2) +
								math.pow(prev.end.y - next.end.y, 2),
							)

							if distance < 2 * bridge_gap &&
							   prev.type == .Bridge {
								panic("Bridges too close")
							}

							start, end: V2
							if isVertical(prev.end, next.end) {
								if prev.end.y < next.end.y { 	// going down
									start = cross + {0, -bridge_gap}
									end = cross + {0, bridge_gap}
								} else { 	// going up
									start = cross + {0, bridge_gap}
									end = cross + {0, -bridge_gap}
									panic("Upward edges not supported")
								}
							} else {
								if prev.end.x < next.end.x { 	// going right
									start = cross + {-bridge_gap, 0}
									end = cross + {bridge_gap, 0}
								} else { 	// going left
									start = cross + {bridge_gap, 0}
									end = cross + {-bridge_gap, 0}
								}
							}

							inserted := insertBridge(
								segments_to_insert_bridge_into,
								idx,
								start,
								end,
							)
							if !inserted {panic("No space for bridge")}
						}
					}
				}
			}
		}
	}

	return graph_size, true
}

@(private = "file")
graph_fill_predecessors_of :: proc(
	graph: ^Graph,
	offset: NodeOffset,
	result: ^[dynamic]NodeOffset,
) {
	clear(result)
	for &edge in graph.edges {
		if edge.to == offset {
			append(result, edge.from)
		}
	}
}

@(private = "file")
graph_fill_children_of :: proc(
	graph: ^Graph,
	offset: NodeOffset,
	result: ^[dynamic]NodeOffset,
) {
	clear(result)
	for &edge in graph.edges {
		if edge.from == offset {
			append(result, edge.to)
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
		if edge.from == node_offset {
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
		if object_start == nil {
			panic("object_start is nil")
		}
		log.infof(
			"%d - %s",
			uintptr(object_start) - uintptr(graph),
			name,
			location = loc,
		)
	}
}

calculate_memory :: proc(sum, new_mem, align: int) -> int {
	aligned_sum := mem.align_forward_int(sum, align)
	return aligned_sum + new_mem
}

map_capacity :: proc(n: int) -> int {
	return (4 * n + 2) / 3
}

map_mem_ussage :: proc(n: int, $T: typeid/map[$K]$V) -> int {
	return int(
		runtime.map_total_allocation_size(
			uintptr(max(n, 8)),
			runtime.map_info(map[$K]$V),
		),
	)
}

// finds a sibling node next to `node` on the other side of vertical_gutter
// if no sibling is found, returns self
sibling :: proc(
	graph: ^Graph,
	node: ^Node,
	node_offset: NodeOffset,
	vertical_gutter_pos: int,
) -> NodeOffset {
	direction := vertical_gutter_pos == int(node.position.x) ? i32(-1) : i32(1)

	sibling_x := node.position.x + direction
	for other_node, offset in graph.nodes {
		if other_node.position.y == node.position.y &&
		   other_node.position.x == sibling_x {
			return NodeOffset(offset)
		}
	}

	// no sibling found, return self
	return node_offset
}
