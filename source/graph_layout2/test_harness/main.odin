package test_harness

import gl2 "../"
import "core:fmt"

V2 :: [2]f32

Node :: struct {
	id: int,
}

Edge :: struct {
	from: int,
	to:   int,
}

// Dummy debug callbacks
debug_draw_rect :: proc(pos: V2, size: V2, color: [4]u8, text: string) {
	// no-op
}

debug_new_section :: proc(name: string) {
	// no-op
}

main :: proc() {
	fmt.println("=== Graph Layout Test Harness ===")
	fmt.println()

	test_graph3()
}

test_graph3 :: proc() {
	fmt.println("--- Test Graph 3 ---")

	nodes := [?]Node {
		{id = 1},
		{id = 2},
		{id = 3},
		{id = 5},
		{id = 6},
		{id = 7},
		{id = 8},
		{id = 9},
	}
	edges := [?]Edge {
		{from = 1, to = 2},
		{from = 2, to = 3},
		{from = 5, to = 6},
		{from = 7, to = 8},
		{from = 8, to = 9},
	}

	max_node_size := V2{100, 50}

	graph: gl2.Graph
	gl2.graph_init(
		&graph,
		u16(len(nodes)),
		u16(len(edges)),
		max_node_size,
		context.allocator,
		debug_draw_rect = debug_draw_rect,
		debug_new_section = debug_new_section,
	)

	for node in nodes {
		ok := gl2.graph_node_add(&graph, u64(node.id))
		assert(ok)
	}

	for edge in edges {
		ok := gl2.graph_edge_add(&graph, u64(edge.from), u64(edge.to))
		assert(ok)
	}

	gl2.graph_layout_compute(&graph)

	fmt.println()
	fmt.println("--- Results ---")
	for i: u16 = 1; i < u16(len(graph.nodes)); i += 1 {
		node := graph.nodes[i]
		fmt.printf(
			"Node[%d] eid:%d, column:%d layer:%d\n",
			i,
			node.external_id,
			node.column,
			node.layer,
		)
	}

	// Verify node 8 (eid=9) is in column 2
	// Node 8 has predecessor Node 6 (eid=8) which is in layer 1 column 2
	// With max_layer_size=3, layer 2 can have columns 0,1,2
	// Node eid=3 (barycenter 0) → col 0, Node eid=9 (barycenter 2) → col 2
	node8 := graph.nodes[8]
	fmt.println()
	if node8.column == 2 {
		fmt.println("PASS: Node 8 (eid=9) is correctly in column 2")
	} else {
		fmt.printf("FAIL: Node 8 (eid=9) is in column %d, expected column 2\n", node8.column)
	}
}
