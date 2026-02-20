package graph_layout2

import "base:runtime"
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

DEBUG: bool : true

ExternalID :: u64

Graph :: struct {
	allocator:           mem.Allocator,
	nodes:               #soa[dynamic]Node,
	edges:               #soa[dynamic]Edge,
	segments:            #soa[dynamic]Segment,
	external_id_to_node: map[ExternalID]NodeHandle,
	node_size:           V2,
	debug_draw_rect:     proc(pos: V2, size: V2, color: [4]u8, text: string),
	debug_new_section:   proc(name: string),
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
	id:          NodeHandle,
	external_id: ExternalID,
	in_edges:    EdgeHandle,
	out_edges:   EdgeHandle,

	// layer assignment
	stack_next:  NodeHandle,
	stack_prev:  NodeHandle,
	layer:       u16,

	// columns
	column:      u16,
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

	g.debug_draw_rect = debug_draw_rect
	g.debug_new_section = debug_new_section
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

	return {f32(150 * node.column), f32(150 * node.layer)}, true
}

graph_edge_add :: proc(g: ^Graph, from_id, to_id: ExternalID) -> bool {
	fmt.println("ADD EDGE ", from_id, " -> ", to_id)
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

		fmt.println("starting tree walk for node ", node_layer1.id.offset, i)

		stack_top: #soa^#soa[dynamic]Node = nil
		node_stack_push(&stack_top, node_layer1)

		for { 	// go through stack of edges
			node := node_stack_pop(g, &stack_top)
			if node == nil {
				fmt.println(
					"done with tree walk for node ",
					node_layer1.id.offset,
					i,
				)
				break
			}

			if node.out_edges == {} {
				fmt.println(
					"node ",
					node.id.offset,
					" has no out edges, skipping",
				)
				continue
			}

			start_edge := edge_get(g, node.out_edges)
			fmt.println(
				"processing out edges for node ",
				node.id.offset,
				", starting with edge ",
				start_edge.id.offset,
			)
			edge := start_edge
			for {
				fmt.println(
					"  processing edge ",
					edge.id.offset,
					" to node ",
					edge.dst.offset,
				)
				next_node := node_get(g, edge.dst)
				next_node.layer = max(next_node.layer, node.layer + 1)
				node_stack_push(&stack_top, next_node)

				fmt.println(
					"    setting node ",
					next_node.id.offset,
					" to layer ",
					next_node.layer,
				)

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
			return len(g.nodes)
		},
		swap = proc(it: sort.Interface, a, b: int) {
			g := (^Graph)(it.collection)
			nodes := &g.nodes
			ah := nodes[a].id
			bh := nodes[b].id
			swap(g, &ah, &bh)
		},
		less = proc(it: sort.Interface, a, b: int) -> bool {
			g := (^Graph)(it.collection)
			return g.nodes[a].layer < g.nodes[b].layer
		},
		collection = g,
	}

	sort.sort(si)

	// ------ ASSIGN ROWS ------

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

	debug_draw_section(g, "END")
	debug_draw_nodes_split_by_layer(g)

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
		fmt.println("stack is empty, cannot pop")
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

	when DEBUG {
		fmt.printf("%*s------ %s ------\n", 2 * indent, "", name)
		for i: u16 = 1; i < u16(len(g.nodes)); i += 1 {
			node := g.nodes[i]
			fmt.printf(
				"%*sNode[%d] id:%d eid:%d, row:%d layer:%d in_edges=%d, out_edges=%d\n",
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
	}
}

debug_draw_nodes_order :: proc(g: ^Graph, base_y: f32 = 0) {
	for i: u16 = 1; i < u16(len(g.nodes)); i += 1 {
		node := g.nodes[i]
		pos := V2{f32(100 * i), base_y}
		g.debug_draw_rect(
			pos,
			{f32(80), f32(80)},
			[4]u8{0, 255, 0, 255},
			fmt.tprintf("n%d", i),
		)
	}
}

debug_draw_nodes_split_by_layer :: proc(g: ^Graph, base_y: f32 = 0) {
	row := 0
	x_offset := -100 // start with -100 so that the first node in a layer is at x=0
	prev := g.nodes[0]
	for i: u16 = 1; i < u16(len(g.nodes)); i += 1 {
		curr := g.nodes[i]
		if prev.layer != curr.layer {
			row += 1
			x_offset = 0
		} else {
			x_offset += 100
		}
		prev = curr

		pos := V2{f32(x_offset), base_y + f32(100 * row)}

		fmt.println(pos)
		g.debug_draw_rect(
			pos,
			{f32(80), f32(80)},
			[4]u8{0, 0, 255, 255},
			fmt.tprintf("x%d", i),
		)
	}
}

debug_draw_section :: proc(g: ^Graph, name: string) {
	when DEBUG {
		g.debug_new_section(name)
	}
}
debug_draw_rect :: proc(
	g: ^Graph,
	pos: V2,
	size: V2,
	color: [4]u8,
	text: string,
) {
	when DEBUG {
		g.debug_draw_rect(pos, size, color, text)
	}
}
