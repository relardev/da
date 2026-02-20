#+feature dynamic-literals
package test_harness

import gl2 "../"
import "core:fmt"
import "core:testing"

// Test case structure for optimal_assign_layer tests
OptimalAssignTest :: struct {
	name:       string,
	n_slots:    int, // Total available slots (like layer array size)
	items:      []struct {
		barycenter: f32,
	}, // Nodes with their barycenter values
	want_cols:  []u16, // Expected column assignments for each item
}

@(test)
test_optimal_assign_layer :: proc(t: ^testing.T) {
	tests: []OptimalAssignTest = {
		{
			name    = "Empty layer",
			n_slots = 3,
			items   = {},
			want_cols = {},
		},
		{
			name    = "Single item rounding to nearest",
			n_slots = 5,
			items   = {{barycenter = 2.6}},
			want_cols = {3}, // rounds to 3
		},
		{
			name    = "Single item clamp left",
			n_slots = 4,
			items   = {{barycenter = -3.1}},
			want_cols = {0}, // clamped to 0
		},
		{
			name    = "Single item clamp right",
			n_slots = 4,
			items   = {{barycenter = 10.0}},
			want_cols = {3}, // clamped to n-1
		},
		{
			name    = "Two items centered with gap",
			n_slots = 5,
			items   = {{barycenter = 1.2}, {barycenter = 2.8}},
			want_cols = {1, 3}, // optimal placement
		},
		{
			name    = "Three items with constrained ends",
			n_slots = 5,
			items   = {{barycenter = 0.2}, {barycenter = 2.1}, {barycenter = 4.4}},
			want_cols = {0, 2, 4},
		},
		{
			name    = "Fully occupied - sequential assignment",
			n_slots = 4,
			items   = {
				{barycenter = 0.9},
				{barycenter = 1.1},
				{barycenter = 2.4},
				{barycenter = 3.7},
			},
			want_cols = {0, 1, 2, 3},
		},
		{
			name    = "Equal barycenters - maintains order",
			n_slots = 5,
			items   = {
				{barycenter = 2.0},
				{barycenter = 2.0},
				{barycenter = 2.0},
			},
			want_cols = {1, 2, 3}, // centered around 2
		},
		{
			name    = "Far-right clustering",
			n_slots = 7,
			items   = {
				{barycenter = 4.7},
				{barycenter = 5.1},
				{barycenter = 5.9},
			},
			want_cols = {4, 5, 6},
		},
		{
			name    = "Fix order - unsorted barycenters",
			n_slots = 3,
			items   = {{barycenter = 0.5}, {barycenter = 1.9}},
			want_cols = {0, 2},
		},
	}

	for tt in tests {
		run_optimal_assign_test(t, tt)
	}
}

run_optimal_assign_test :: proc(t: ^testing.T, tt: OptimalAssignTest) {
	if len(tt.items) == 0 {
		// Empty test - nothing to verify
		return
	}

	// Create a graph with enough capacity
	graph: gl2.Graph
	gl2.graph_init(
		&graph,
		u16(len(tt.items) + 2),
		1, // minimal edge capacity
		{100, 50},
		context.allocator,
	)

	// Add nodes and set their barycenter values
	for item, i in tt.items {
		ok := gl2.graph_node_add(&graph, u64(i + 1))
		testing.expect(t, ok, fmt.tprintf("[%s] Failed to add node %d", tt.name, i + 1))

		// Set the barycenter_x directly
		graph.nodes[i + 1].barycenter_x = item.barycenter
		graph.nodes[i + 1].layer = 0
	}

	// Call optimal_assign_layer
	layer_start := 1
	layer_end := len(tt.items) + 1
	gl2.optimal_assign_layer(&graph, layer_start, layer_end, tt.n_slots)

	// Verify results
	for i := 0; i < len(tt.items); i += 1 {
		node_idx := i + 1
		got_col := graph.nodes[node_idx].column
		want_col := tt.want_cols[i]

		testing.expect(
			t,
			got_col == want_col,
			fmt.tprintf(
				"[%s] Node %d (barycenter=%.1f): got column %d, want %d",
				tt.name,
				node_idx,
				tt.items[i].barycenter,
				got_col,
				want_col,
			),
		)
	}
}

// Additional integration test for full barycenter algorithm
@(test)
test_assign_columns_integration :: proc(t: ^testing.T) {
	// Test case: Three chains that should align vertically
	// Chain 1: 1 -> 2 -> 3
	// Chain 2: 5 -> 6
	// Chain 3: 7 -> 8 -> 9

	graph: gl2.Graph
	gl2.graph_init(
		&graph,
		10,
		6,
		{100, 50},
		context.allocator,
	)

	// Add nodes
	nodes := [?]u64{1, 2, 3, 5, 6, 7, 8, 9}
	for id in nodes {
		ok := gl2.graph_node_add(&graph, id)
		testing.expect(t, ok, fmt.tprintf("Failed to add node %d", id))
	}

	// Add edges
	edges := [?][2]u64{{1, 2}, {2, 3}, {5, 6}, {7, 8}, {8, 9}}
	for edge in edges {
		ok := gl2.graph_edge_add(&graph, edge[0], edge[1])
		testing.expect(t, ok, fmt.tprintf("Failed to add edge %d -> %d", edge[0], edge[1]))
	}

	// Run full layout
	gl2.graph_layout_compute(&graph)

	// Verify chain alignment:
	// - Chain 1 (1->2->3) should be in column 0
	// - Chain 2 (5->6) should be in column 1
	// - Chain 3 (7->8->9) should be in column 2

	// Find nodes by external ID and check columns
	expected := map[u64]u16 {
		1 = 0, 2 = 0, 3 = 0, // Chain 1 all in column 0
		5 = 1, 6 = 1, // Chain 2 all in column 1
		7 = 2, 8 = 2, 9 = 2, // Chain 3 all in column 2
	}

	for i: u16 = 1; i < u16(len(graph.nodes)); i += 1 {
		node := graph.nodes[i]
		want_col, found := expected[node.external_id]
		if found {
			testing.expect(
				t,
				node.column == want_col,
				fmt.tprintf(
					"Node eid=%d: got column %d, want %d",
					node.external_id,
					node.column,
					want_col,
				),
			)
		}
	}
}
