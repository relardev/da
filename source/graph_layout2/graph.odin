package graph_layout2

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
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
	layer:       u16,
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

	return {0, f32(100 * node.id.offset)}, true
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

	// topological sort
	if src_id.offset > dst_id.offset {
		print_state(1, g, "BEFORE")
		fmt.println("SWAP ", from_id, " <-> ", to_id)
		swap(g, &src_id, &dst_id)
		print_state(1, g, "AFTER")
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
		dst.layer = max(dst.layer, src.layer + 1)
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
	print_state(0, g, "COMPUE")

	return
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
				"%*sNode[%d] id:%d eid:%d, layer:%d in_edges=%d, out_edges=%d\n",
				2 * (indent + 1),
				"",
				i,
				node.id.offset,
				node.external_id,
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
