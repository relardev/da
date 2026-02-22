package graph_layout2

import "core:fmt"
import "core:log"
import "core:mem"
import "core:sort"
import ts "topological_sort"

_ :: log
_ :: fmt
_ :: ts

V2 :: [2]f32
V2i :: [2]i32

DEBUG_DRAW :: true
DEBUG_PRINT :: true

DEFAULT_NODE_SPACING :: 150.0

ExternalID :: u64

Graph :: struct {
	allocator:           mem.Allocator,
	nodes:               #soa[dynamic]Node,
	edges:               #soa[dynamic]Edge,
	segments:            #soa[dynamic]Segment,
	external_id_to_node: map[ExternalID]NodeHandle,
	node_size:           V2,
	node_spacing:        f32,
	debug_draw_rect:     proc(pos: V2, size: V2, color: [4]u8, text: string),
	debug_new_section:   proc(name: string),

	// barycenter algorithm temporaries
	dp_slots:            #soa[dynamic]DPSlot,
	back_matrix:         []i16,
	sort_indices:        []u16,
	layer_boundaries:    []LayerBoundary,
}

LayerBoundary :: struct {
	start, end: int,
}

// barycenter algorithm DP temporaries
DPSlot :: struct {
	prev: f32,
	curr: f32,
}

EdgeHandle :: struct {
	offset: u16,
}

NodeHandle :: struct {
	offset: u16,
}

SegmentHandle :: struct {
	offset: u16,
}

Node :: struct {
	id:           NodeHandle,
	external_id:  ExternalID,
	in_edges:     EdgeHandle,
	out_edges:    EdgeHandle,

	// layer assignment
	stack_next:   NodeHandle,
	stack_prev:   NodeHandle,
	layer:        u16,

	// columns
	column:       u16,

	// barycenter algorithm
	barycenter_x: f32,
}

Edge :: struct {
	id:       EdgeHandle,
	src:      NodeHandle,
	src_next: EdgeHandle,
	src_prev: EdgeHandle,
	dst:      NodeHandle,
	dst_next: EdgeHandle,
	dst_prev: EdgeHandle,
}

EdgeResult :: struct {
	start:   V2,
	segment: SegmentHandle,
}

Segment :: struct {
	next: SegmentHandle,
	prev: SegmentHandle,
	type: SegmentType,
	end:  V2,
}

SegmentType :: enum {
	Line,
	Bridge,
}

SegmentResult :: struct {
	end:  V2,
	type: SegmentType,
	next: SegmentHandle,
}

graph_init :: proc(
	g: ^Graph,
	node_capacity: u16,
	edge_capacity: u16,
	node_size: V2,
	allocator: mem.Allocator,
	debug_draw_rect: proc(pos: V2, size: V2, color: [4]u8, text: string) = nil,
	debug_new_section: proc(name: string) = nil,
	node_spacing: f32 = DEFAULT_NODE_SPACING,
) {
	nil_alloc := mem.nil_allocator()
	g.nodes = make(#soa[dynamic]Node, 0, node_capacity + 2, allocator)
	g.nodes.allocator = mem.nil_allocator()
	append_soa(&g.nodes, Node{})

	g.edges = make(#soa[dynamic]Edge, 0, edge_capacity + 2, allocator)
	g.edges.allocator = nil_alloc
	append_soa(&g.edges, Edge{})

	segments_max_count := 2 * (edge_capacity * edge_capacity)
	g.segments = make(
		#soa[dynamic]Segment,
		0,
		segments_max_count + 1,
		allocator,
	)
	g.segments.allocator = nil_alloc
	append_soa(&g.segments, Segment{})

	g.external_id_to_node = make(
		map[ExternalID]NodeHandle,
		int(f32(node_capacity) * 1.5),
		allocator,
	)
	g.external_id_to_node.allocator = nil_alloc

	g.node_size = node_size
	g.node_spacing = node_spacing

	g.debug_draw_rect = debug_draw_rect
	g.debug_new_section = debug_new_section

	// barycenter algorithm temporaries
	max_nodes := int(node_capacity + 2)
	g.dp_slots = make(#soa[dynamic]DPSlot, max_nodes, allocator)
	g.dp_slots.allocator = nil_alloc
	g.back_matrix = make([]i16, max_nodes * max_nodes, allocator)
	g.sort_indices = make([]u16, max_nodes, allocator)
	g.layer_boundaries = make([]LayerBoundary, max_nodes, allocator)
}

graph_node_add :: proc(g: ^Graph, id: ExternalID) -> bool {
	if len(g.nodes) + 1 == cap(g.nodes) {
		// No more space for nodes.
		return false
	}

	node := Node {
		id = {offset = u16(len(g.nodes))},
		external_id = id,
	}
	append_soa(&g.nodes, node)

	g.external_id_to_node[id] = node.id
	return true
}

graph_node_read :: proc(g: ^Graph, id: ExternalID) -> (V2, bool) {
	node_id, found := g.external_id_to_node[id]
	if !found {
		return V2{}, false
	}

	node := g.nodes[node_id.offset]

	return {
			g.node_spacing * f32(node.column),
			g.node_spacing * f32(node.layer),
		},
		true
}

graph_edge_add :: proc(g: ^Graph, from_id, to_id: ExternalID) -> bool {
	// fmt.println("ADD EDGE ", from_id, " -> ", to_id)
	if from_id == to_id {
		// No self-loops allowed.
		return false
	}

	src_id, ok := g.external_id_to_node[from_id]
	if !ok {
		return false
	}

	dst_id, ok2 := g.external_id_to_node[to_id]
	if !ok2 {
		return false
	}

	// start topological sort
	if src_id.offset > dst_id.offset {
		swap(g, &src_id, &dst_id)
	}

	edge_id := EdgeHandle {
		offset = u16(len(g.edges)),
	}

	new_edge := Edge {
		id  = edge_id,
		src = src_id,
		dst = dst_id,
	}

	src := node_get(g, src_id)
	{ 	// Link in source node.
		if src.out_edges == {} {
			// First out edge.
			new_edge.src_next = edge_id
			new_edge.src_prev = edge_id
			src.out_edges = edge_id
		} else {
			// Append to existing out edges.
			first_out_edge := edge_get(g, src.out_edges)
			last_out_edge := edge_get(g, first_out_edge.src_prev)

			first_out_edge.src_prev = edge_id
			last_out_edge.src_next = edge_id

			new_edge.src_prev = last_out_edge.id
			new_edge.src_next = first_out_edge.id
		}
	}

	{ 	// Link in destination node.
		dst := node_get(g, dst_id)
		if dst.in_edges == {} {
			// First in edge.
			new_edge.dst_next = edge_id
			new_edge.dst_prev = edge_id
			dst.in_edges = edge_id
		} else {
			// Append to existing in edges.
			first_in_edge := edge_get(g, dst.in_edges)
			last_in_edge := edge_get(g, first_in_edge.dst_prev)

			first_in_edge.dst_prev = edge_id
			last_in_edge.dst_next = edge_id

			new_edge.dst_prev = last_in_edge.id
			new_edge.dst_next = first_in_edge.id
		}
	}

	append_soa(&g.edges, new_edge)

	print_state(1, g, "ADD EDGE END")

	return true
}

graph_edge_read :: proc(
	g: ^Graph,
	from_id, to_id: ExternalID,
) -> (
	EdgeResult,
	bool,
) {
	return {}, true
}

graph_segment_read :: proc(
	g: ^Graph,
	segment_handle: SegmentHandle,
) -> SegmentResult {
	return {}
}

graph_layout_compute :: proc(g: ^Graph) {
	// ------ ASSIGN LAYERS ------
	debug_draw_section(g, "Assign Layers")
	debug_draw_nodes_order(g)
	print_state(0, g, "COMPUE")

	for i: u16 = 1; i < u16(len(g.nodes)); i += 1 {
		node_layer1 := &g.nodes[i]
		if node_layer1.in_edges != {} {
			continue
		}

		// fmt.println("starting tree walk for node ", node_layer1.id.offset, i)

		stack_top: #soa^#soa[dynamic]Node = nil
		node_stack_push(&stack_top, node_layer1)

		for { 	// go through stack of edges
			node := node_stack_pop(g, &stack_top)
			if node == nil {break}
			if node.out_edges == {} {continue}

			start_edge := edge_get(g, node.out_edges)
			edge := start_edge
			for {
				next_node := node_get(g, edge.dst)
				next_node.layer = max(next_node.layer, node.layer + 1)
				node_stack_push(&stack_top, next_node)

				edge = edge_get(g, edge.src_next)
				if edge.id == start_edge.id {
					break
				}
			}
		}
	}

	// ------- FINISH SORTING USING LAYERS ------

	si := sort.Interface {
		len = proc(it: sort.Interface) -> int {
			g := (^Graph)(it.collection)
			return len(g.nodes) - 1 // exclude sentinel at index 0
		},
		swap = proc(it: sort.Interface, a, b: int) {
			g := (^Graph)(it.collection)
			nodes := g.nodes[1:]
			ah := nodes[a].id
			bh := nodes[b].id
			swap(g, &ah, &bh)
		},
		less = proc(it: sort.Interface, a, b: int) -> bool {
			g := (^Graph)(it.collection)
			nodes := g.nodes[1:]
			if nodes[a].layer != nodes[b].layer {
				return nodes[a].layer < nodes[b].layer
			}
			return nodes[a].external_id < nodes[b].external_id
		},
		collection = g,
	}

	sort.sort(si)

	// ------ ASSIGN SOME COLUMNS ------

	column: u16 = 0
	last_layer: u16 = 0
	for i: u16 = 1; i < u16(len(g.nodes)); i += 1 {
		node := &g.nodes[i]
		if node.layer != last_layer {
			last_layer = node.layer
			column = 0
		}
		node.column = column
		column += 1
	}

	debug_draw_section(g, "before")
	debug_draw_nodes_split_by_layer(g)

	// ------ ASSIGN PROPER COLUMNS ------

	assign_columns(g)

	debug_draw_section(g, "after")
	// debug_draw_nodes_split_by_layer(g)

	debug_draw_nodes_proper_position(g)

	print_state(0, g, "COMPUE END")
}

node_stack_push :: proc(
	stack_top: ^#soa^#soa[dynamic]Node,
	new_node: #soa^#soa[dynamic]Node,
) {
	if stack_top^ == nil {
		new_node.stack_prev = {}
		new_node.stack_next = {}
	} else {
		stack_top^.stack_next = new_node.id
		new_node.stack_prev = stack_top^.id
	}
	stack_top^ = new_node
}

node_stack_pop :: proc(
	g: ^Graph,
	stack_top: ^#soa^#soa[dynamic]Node,
) -> #soa^#soa[dynamic]Node {
	popped := stack_top^
	if popped == nil {
		return nil
	}

	if popped.stack_prev == {} {
		// Stack is now empty.
		stack_top^ = nil
	} else {
		stack_top^ = node_get(g, popped.stack_prev)
		stack_top^.stack_next = {}
	}

	return popped
}

swap :: proc(g: ^Graph, ah: ^NodeHandle, bh: ^NodeHandle) {
	a := g.nodes[ah.offset]
	b := g.nodes[bh.offset]
	a.id, b.id = b.id, a.id
	g.nodes[ah.offset], g.nodes[bh.offset] = b, a

	update_edges_src :: proc(
		g: ^Graph,
		starting_edge: EdgeHandle,
		to: NodeHandle,
	) {
		if starting_edge == {} {return}

		edge := edge_get(g, starting_edge)
		for {
			edge.src = to
			if edge.src_next == starting_edge {
				break
			}

			edge = edge_get(g, edge.src_next)
		}
	}

	update_edges_src(g, a.out_edges, bh^)
	update_edges_src(g, b.out_edges, ah^)

	update_edges_dst :: proc(
		g: ^Graph,
		starting_edge: EdgeHandle,
		to: NodeHandle,
	) {
		if starting_edge == {} {return}
		edge := edge_get(g, starting_edge)
		for {
			edge.dst = to
			if edge.dst_next == starting_edge {
				break
			}

			edge = edge_get(g, edge.dst_next)
		}
	}

	update_edges_dst(g, a.in_edges, bh^)
	update_edges_dst(g, b.in_edges, ah^)

	g.external_id_to_node[a.external_id] = bh^
	g.external_id_to_node[b.external_id] = ah^

	ah^, bh^ = bh^, ah^
}

edge_get :: proc(g: ^Graph, eh: EdgeHandle) -> (edge: #soa^#soa[dynamic]Edge) {
	edge_ptr := &g.edges[eh.offset]
	assert(edge_ptr.id != {})
	return edge_ptr
}

node_get :: proc(g: ^Graph, nh: NodeHandle) -> (node: #soa^#soa[dynamic]Node) {
	node_ptr := &g.nodes[nh.offset]
	assert(node_ptr.id != {})
	return node_ptr
}

print_state :: proc(indent: int, g: ^Graph, name: string) {
	indent_proc :: proc(n: int) {
		for i: int = 0; i < n; i += 1 {
			fmt.print("  ")
		}
	}

	when !DEBUG_PRINT {
		return
	}

	fmt.printf("%*s------ %s ------\n", 2 * indent, "", name)
	for i: u16 = 1; i < u16(len(g.nodes)); i += 1 {
		node := g.nodes[i]
		fmt.printf(
			"%*sNode[%d] id:%d eid:%d, column:%d layer:%d in_edges=%d, out_edges=%d\n",
			2 * (indent + 1),
			"",
			i,
			node.id.offset,
			node.external_id,
			node.column,
			node.layer,
			node.in_edges.offset,
			node.out_edges.offset,
		)
	}

	fmt.println()

	for i: u16 = 1; i < u16(len(g.edges)); i += 1 {
		edge := g.edges[i]
		fmt.printf(
			"%*sEdge[%d] id:%d: src=%d, dst=%d, src_next=%d, src_prev=%d, dst_next=%d, dst_prev=%d\n",
			2 * (indent + 1),
			"",
			i,
			edge.id.offset,
			edge.src.offset,
			edge.dst.offset,
			edge.src_next.offset,
			edge.src_prev.offset,
			edge.dst_next.offset,
			edge.dst_prev.offset,
		)
	}

	fmt.println()

	for k, v in g.external_id_to_node {
		fmt.printf(
			"%*sExternalID %d -> NodeHandle %d\n",
			2 * (indent + 1),
			"",
			k,
			v.offset,
		)
	}
}

assign_columns :: proc(g: ^Graph) {
	node_count := len(g.nodes)
	if node_count <= 1 {
		return
	}

	// First pass: find maximum layer size
	max_layer_size := 0
	{
		layer_start := 1
		for layer_start < node_count {
			current_layer := g.nodes[layer_start].layer
			layer_end := layer_start
			for layer_end < node_count &&
			    g.nodes[layer_end].layer == current_layer {
				layer_end += 1
			}
			layer_size := layer_end - layer_start
			if layer_size > max_layer_size {
				max_layer_size = layer_size
			}
			layer_start = layer_end
		}
	}

	// Initialize barycenter_x and column for all nodes, centered within max_layer_size
	{
		layer_start := 1
		for layer_start < node_count {
			current_layer := g.nodes[layer_start].layer
			layer_end := layer_start
			for layer_end < node_count &&
			    g.nodes[layer_end].layer == current_layer {
				layer_end += 1
			}
			layer_size := layer_end - layer_start
			offset := f32(max_layer_size - layer_size) / 2.0
			for i := layer_start; i < layer_end; i += 1 {
				pos := offset + f32(i - layer_start)
				g.nodes[i].barycenter_x = pos
				g.nodes[i].column = u16(pos)
			}
			layer_start = layer_end
		}
	}

	// Collect layer boundaries (nodes are sorted by layer)
	num_layers := 0
	{
		layer_start := 1
		for layer_start < node_count {
			current_layer := g.nodes[layer_start].layer
			layer_end := layer_start
			for layer_end < node_count &&
			    g.nodes[layer_end].layer == current_layer {
				layer_end += 1
			}
			g.layer_boundaries[num_layers] = {layer_start, layer_end}
			num_layers += 1
			layer_start = layer_end
		}
	}

	// 11 iterations alternating forward/backward passes (odd count to end on forward)
	for iter := 0; iter < 11; iter += 1 {
		direction := iter % 2

		for li := 0; li < num_layers; li += 1 {
			// Forward pass: top-to-bottom; Backward pass: bottom-to-top
			layer_idx := direction == 0 ? li : (num_layers - 1 - li)
			layer_start := g.layer_boundaries[layer_idx].start
			layer_end := g.layer_boundaries[layer_idx].end

			// Compute barycenter for each node in layer
			for i := layer_start; i < layer_end; i += 1 {
				sum: f32 = 0
				count := 0

				if direction == 0 {
					// Forward pass: use predecessors (in_edges)
					first_edge := g.nodes[i].in_edges
					if first_edge.offset != 0 {
						edge_handle := first_edge
						for {
							edge := edge_get(g, edge_handle)
							pred := node_get(g, edge.src)
							sum += pred.barycenter_x
							count += 1

							edge_handle = edge.dst_next
							if edge_handle.offset == first_edge.offset {
								break
							}
						}
					}
				} else {
					// Backward pass: use children (out_edges)
					first_edge := g.nodes[i].out_edges
					if first_edge.offset != 0 {
						edge_handle := first_edge
						for {
							edge := edge_get(g, edge_handle)
							child := node_get(g, edge.dst)
							sum += child.barycenter_x
							count += 1

							edge_handle = edge.src_next
							if edge_handle.offset == first_edge.offset {
								break
							}
						}
					}
				}

				if count > 0 {
					g.nodes[i].barycenter_x = sum / f32(count)
				}
			}

			// Apply optimal DP assignment for this layer
			// Use max_layer_size as n_slots to allow gaps in column assignment
			optimal_assign_layer(g, layer_start, layer_end, max_layer_size)

			// Update barycenter_x to match assigned column
			for i := layer_start; i < layer_end; i += 1 {
				g.nodes[i].barycenter_x = f32(g.nodes[i].column)
			}
		}
	}
}

// Assigns optimal discrete column positions to nodes in a layer using DP
// layer_start: first node index (inclusive)
// layer_end: last node index (exclusive)
// n_slots: number of available column slots
optimal_assign_layer :: proc(
	g: ^Graph,
	layer_start, layer_end: int,
	n_slots: int,
) {
	m := layer_end - layer_start // number of items to place
	if m == 0 {
		return
	}

	n := n_slots
	if n < m {
		n = m // need at least as many slots as items
	}

	// Build sorted indices array (don't move nodes, just track order)
	// Initialize sort_indices with node indices
	for i := 0; i < m; i += 1 {
		g.sort_indices[i] = u16(layer_start + i)
	}

	// Sort indices by barycenter_x using insertion sort
	for i := 1; i < m; i += 1 {
		j := i
		for j > 0 {
			idx_j := g.sort_indices[j]
			idx_j_1 := g.sort_indices[j - 1]
			if g.nodes[idx_j].barycenter_x < g.nodes[idx_j_1].barycenter_x {
				g.sort_indices[j] = idx_j_1
				g.sort_indices[j - 1] = idx_j
				j -= 1
			} else {
				break
			}
		}
	}

	// Trivial case: single node
	if m == 1 {
		node_idx := g.sort_indices[0]
		best := int(g.nodes[node_idx].barycenter_x + 0.5)
		if best < 0 {
			best = 0
		}
		if best >= n {
			best = n - 1
		}
		g.nodes[node_idx].column = u16(best)
		return
	}

	// If m == n, assign columns 0..m-1 in sorted order
	if m == n {
		for i := 0; i < m; i += 1 {
			node_idx := g.sort_indices[i]
			g.nodes[node_idx].column = u16(i)
		}
		return
	}

	// General DP case: m items, n slots, m < n
	INF: f32 = 3.4e38
	CENTER_BIAS: f32 = 1e-6
	center := f32(n - 1) / 2.0

	// Initialize dp_prev
	for j := 0; j < n; j += 1 {
		g.dp_slots[j].prev = INF
	}

	// First item (k=0)
	upper0 := n - (m - 1)
	if upper0 > n - 1 {
		upper0 = n - 1
	}
	node0_idx := g.sort_indices[0]
	x0 := g.nodes[node0_idx].barycenter_x
	for j := 0; j <= upper0; j += 1 {
		d := f32(j) - x0
		dc := f32(j) - center
		g.dp_slots[j].prev = d * d + CENTER_BIAS * dc * dc
	}

	// DP transitions for k = 1..m-1
	for k := 1; k < m; k += 1 {
		for j := 0; j < n; j += 1 {
			g.dp_slots[j].curr = INF
		}

		j_min := k
		j_max := n - (m - 1 - k)
		if j_max > n - 1 {
			j_max = n - 1
		}

		prev_min := k - 1
		prev_max := n - (m - 1 - (k - 1))
		if prev_max > n - 1 {
			prev_max = n - 1
		}

		nodek_idx := g.sort_indices[k]
		xk := g.nodes[nodek_idx].barycenter_x
		best_cost: f32 = INF
		best_idx := -1

		for j := j_min; j <= j_max; j += 1 {
			prev_candidate := j - 1
			if prev_candidate >= prev_min && prev_candidate <= prev_max {
				cost_cand := g.dp_slots[prev_candidate].prev
				if cost_cand < best_cost {
					best_cost = cost_cand
					best_idx = prev_candidate
				}
			}
			if best_idx >= 0 {
				d := f32(j) - xk
				dc := f32(j) - center
				g.dp_slots[j].curr = best_cost + d * d + CENTER_BIAS * dc * dc
				g.back_matrix[k * n + j] = i16(best_idx)
			}
		}

		// Swap prev and curr
		for j := 0; j < n; j += 1 {
			g.dp_slots[j].prev = g.dp_slots[j].curr
		}
	}

	// Find best terminal position
	k_last := m - 1
	best_final_cost: f32 = INF
	best_final_j := -1
	term_min := k_last
	term_max := n - 1
	for j := term_min; j <= term_max; j += 1 {
		c := g.dp_slots[j].prev
		if c < best_final_cost {
			best_final_cost = c
			best_final_j = j
		}
	}

	// Backtrack to find all slot assignments
	j := best_final_j
	for k := k_last; k >= 0; k -= 1 {
		node_idx := g.sort_indices[k]
		g.nodes[node_idx].column = u16(j)
		if k > 0 {
			j = int(g.back_matrix[k * n + j])
		}
	}
}

DEBUG_RECT_SIDE :: 40
DEBUG_PADDING :: 10
DEBUG_RECT_SIZE: V2 = {DEBUG_RECT_SIDE, DEBUG_RECT_SIDE}

debug_draw_nodes_order :: proc(g: ^Graph, base_y: f32 = 0) {
	when !DEBUG_DRAW {
		return
	}

	if g.debug_draw_rect == nil {
		return
	}

	dist_between_rects :: DEBUG_RECT_SIDE + DEBUG_PADDING

	for i: u16 = 1; i < u16(len(g.nodes)); i += 1 {
		node := g.nodes[i]
		pos := V2{dist_between_rects * f32(i), base_y}
		g.debug_draw_rect(
			pos,
			DEBUG_RECT_SIZE,
			[4]u8{0, 255, 0, 255},
			fmt.tprintf("n%d", node.external_id),
		)
	}
}

debug_draw_nodes_split_by_layer :: proc(g: ^Graph, base_y: f32 = 0) {
	when !DEBUG_DRAW {
		return
	}

	if g.debug_draw_rect == nil {
		return
	}

	dist_between_rects := DEBUG_RECT_SIDE + DEBUG_PADDING

	row := 0
	x_offset := -1 * dist_between_rects
	prev := g.nodes[0]
	for i: u16 = 1; i < u16(len(g.nodes)); i += 1 {
		curr := g.nodes[i]
		if prev.layer != curr.layer {
			row += 1
			x_offset = 0
		} else {
			x_offset += dist_between_rects
		}
		prev = curr

		pos := V2{f32(x_offset), base_y + f32(dist_between_rects * row)}

		g.debug_draw_rect(
			pos,
			DEBUG_RECT_SIZE,
			[4]u8{0, 0, 255, 255},
			fmt.tprintf("x%d", i),
		)
	}
}

debug_draw_nodes_proper_position :: proc(g: ^Graph) {
	when !DEBUG_DRAW {
		return
	}

	if g.debug_draw_rect == nil {
		return
	}

	for i: u16 = 1; i < u16(len(g.nodes)); i += 1 {
		node := g.nodes[i]
		pos :=
			(DEBUG_PADDING + DEBUG_RECT_SIDE) *
			V2{f32(node.column), f32(node.layer)}
		g.debug_draw_rect(
			pos,
			DEBUG_RECT_SIZE,
			[4]u8{255, 0, 0, 255},
			fmt.tprintf("x%d", i),
		)
	}
}

debug_draw_section :: proc(g: ^Graph, name: string) {
	when DEBUG_DRAW {
		if g.debug_new_section != nil {
			g.debug_new_section(name)
		}
	}
}
debug_draw_rect :: proc(
	g: ^Graph,
	pos: V2,
	size: V2,
	color: [4]u8,
	text: string,
) {
	when DEBUG_DRAW {
		if g.debug_draw_rect != nil {
			g.debug_draw_rect(pos, size, color, text)
		}
	}
}
