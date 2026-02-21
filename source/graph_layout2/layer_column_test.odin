#+feature dynamic-literals
package graph_layout2

import "core:fmt"
import "core:testing"

// Test case structure for full graph layout tests (layer + column assignment)
GraphLayoutTest :: struct {
	name:             string,
	nodes:            []u64, // External IDs of nodes
	edges:            [][2]u64, // [from, to] pairs
	expected_layers:  []u16, // Expected layer for each node (indexed by node order)
	expected_columns: []u16, // Expected column for each node (indexed by node order)
}

@(test)
test_graph_layout :: proc(t: ^testing.T) {
	tests: []GraphLayoutTest = {
		{
			name             = "Pyramid graph",
			nodes            = {0, 1, 2, 3, 4, 5, 6, 7, 8},
			edges            = {
				// Layer 0 -> Layer 1
				{0, 1},
				{0, 2},
				{0, 3},
				// Layer 1 -> Layer 2
				{1, 4},
				{1, 5},
				{2, 6},
				{3, 7},
				{3, 8},
			},
			expected_layers  = {0, 1, 1, 1, 2, 2, 2, 2, 2},
			expected_columns = {2, 1, 2, 3, 0, 1, 2, 3, 4},
		},
		{
			name             = "Inverted pyramid graph",
			nodes            = {0, 1, 2, 3, 4, 5, 6, 7, 8},
			edges            = {
				// Layer 0 -> Layer 1
				{0, 5},
				{1, 5},
				{2, 6},
				{3, 7},
				{4, 7},
				// Layer 1 -> Layer 2
				{5, 8},
				{6, 8},
				{7, 8},
			},
			expected_layers  = {0, 0, 0, 0, 0, 1, 1, 1, 2},
			expected_columns = {0, 1, 2, 3, 4, 1, 2, 3, 2},
		},
	}

	for tt in tests {
		run_graph_layout_test(t, tt)
	}
}

run_graph_layout_test :: proc(t: ^testing.T, tt: GraphLayoutTest) {
	if len(tt.nodes) == 0 {
		return
	}

	// Validate test case consistency
	testing.expect(
		t,
		len(tt.nodes) == len(tt.expected_layers),
		fmt.tprintf(
			"[%s] nodes count (%d) != expected_layers count (%d)",
			tt.name,
			len(tt.nodes),
			len(tt.expected_layers),
		),
	)
	testing.expect(
		t,
		len(tt.nodes) == len(tt.expected_columns),
		fmt.tprintf(
			"[%s] nodes count (%d) != expected_columns count (%d)",
			tt.name,
			len(tt.nodes),
			len(tt.expected_columns),
		),
	)

	// Create a graph with enough capacity
	graph: Graph
	graph_init(
		&graph,
		u16(len(tt.nodes) + 2),
		u16(len(tt.edges) + 2),
		{100, 50},
		context.allocator,
	)

	// Add nodes
	for id, i in tt.nodes {
		ok := graph_node_add(&graph, id)
		testing.expect(
			t,
			ok,
			fmt.tprintf(
				"[%s] Failed to add node %d (index %d)",
				tt.name,
				id,
				i,
			),
		)
	}

	// Add edges
	for edge in tt.edges {
		ok := graph_edge_add(&graph, edge[0], edge[1])
		testing.expect(
			t,
			ok,
			fmt.tprintf(
				"[%s] Failed to add edge %d -> %d",
				tt.name,
				edge[0],
				edge[1],
			),
		)
	}

	// Run full layout computation
	graph_layout_compute(&graph)

	// Verify results for each node
	for id, i in tt.nodes {
		node_handle, found := graph.external_id_to_node[id]
		testing.expect(
			t,
			found,
			fmt.tprintf("[%s] Node %d not found in graph", tt.name, id),
		)
		if !found {
			continue
		}

		node := graph.nodes[node_handle.offset]
		want_layer := tt.expected_layers[i]
		want_column := tt.expected_columns[i]

		testing.expect(
			t,
			node.layer == want_layer,
			fmt.tprintf(
				"[%s] Node %d: got layer %d, want %d",
				tt.name,
				id,
				node.layer,
				want_layer,
			),
		)

		testing.expect(
			t,
			node.column == want_column,
			fmt.tprintf(
				"[%s] Node %d: got column %d, want %d",
				tt.name,
				id,
				node.column,
				want_column,
			),
		)
	}
}
