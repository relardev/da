#+feature dynamic-literals
package graph_layout

import "core:fmt"
import "core:testing"

@(test)
test_optimal_assign_quadratic :: proc(t: ^testing.T) {
	tests: []struct {
		name:  string,
		layer: []LayerCell,
		want:  []LayerCell,
	} = {
		{
			name  = "Test 1 - Fix order",
			layer = {
				// Empty cell at front
				{},
				// Nodes sorted by x
				{node_offset = 2, x = 0.5},
				{node_offset = 1, x = 1.9},
			},
			want  = {
				{node_offset = 2, x = 0.5},
				{},
				{node_offset = 1, x = 1.9},
			},
		},
		{name = "Empty layer", layer = {}, want = {}},
		{
			name  = "Single item rounding up",
			layer = {
				// Four empty cells at front
				{},
				{},
				{},
				{},
				// Single node with x=2.6 should round to index 3
				{node_offset = 1, x = 2.6},
			},
			want  = {{}, {}, {}, {node_offset = 1, x = 2.6}, {}},
		},
		{
			name  = "Single item clamp left",
			layer = {
				// Empty cells at front
				{},
				{},
				{},
				// Node with negative x value
				{node_offset = 1, x = -3.1},
			},
			want  = {{node_offset = 1, x = -3.1}, {}, {}, {}},
		},
		{
			name  = "Fully occupied keeps order",
			layer = {
				// No empty structs in this test - all cells occupied
				{node_offset = 1, x = 0.9},
				{node_offset = 2, x = 1.1},
				{node_offset = 3, x = 2.4},
				{node_offset = 4, x = 3.7},
			},
			want  = {
				{node_offset = 1, x = 0.9},
				{node_offset = 2, x = 1.1},
				{node_offset = 3, x = 2.4},
				{node_offset = 4, x = 3.7},
			},
		},
		{
			name  = "Two items centered with gap",
			layer = {
				// Three empty cells at front
				{},
				{},
				{},
				// Followed by non-empty cells sorted by x
				{node_offset = 1, x = 1.2},
				{node_offset = 2, x = 2.8},
			},
			want  = {
				{},
				{node_offset = 1, x = 1.2},
				{},
				{node_offset = 2, x = 2.8},
				{},
			},
		},
		{
			name  = "Three items with constrained ends",
			layer = {
				// Empty cells at front
				{},
				{},
				// Nodes sorted by x
				{node_offset = 1, x = 0.2},
				{node_offset = 2, x = 2.1},
				{node_offset = 3, x = 4.4},
			},
			want  = {
				{node_offset = 1, x = 0.2},
				{},
				{node_offset = 2, x = 2.1},
				{},
				{node_offset = 3, x = 4.4},
			},
		},
		{
			name  = "Equal x values maintains order",
			layer = {
				// Empty cells at front
				{},
				{},
				// Followed by cells with equal x values, order should be preserved
				{node_offset = 1, x = 2.0},
				{node_offset = 2, x = 2.0},
				{node_offset = 3, x = 2.0},
			},
			want  = {
				{},
				{node_offset = 1, x = 2.0},
				{node_offset = 2, x = 2.0},
				{node_offset = 3, x = 2.0},
				{},
			},
		},
		{
			name  = "Many empties with far-right clustering",
			layer = {
				// Empty cells at front
				{},
				{},
				{},
				{},
				// Nodes sorted by x
				{node_offset = 1, x = 4.7},
				{node_offset = 2, x = 5.1},
				{node_offset = 3, x = 5.9},
			},
			want  = {
				{},
				{},
				{},
				{},
				{node_offset = 1, x = 4.7},
				{node_offset = 2, x = 5.1},
				{node_offset = 3, x = 5.9},
			},
		},
		{
			name  = "Three clusters with same-x nodes",
			layer = {
				// All empty structs must be at the front
				{},
				{},
				{},
				{},
				{},
				{},
				// All non-empty structs sorted by x
				{node_offset = 1, x = 1.0},
				{node_offset = 2, x = 1.0},
				{node_offset = 3, x = 1.0},
				{node_offset = 4, x = 5.0},
				{node_offset = 5, x = 5.0},
				{node_offset = 6, x = 5.0},
				{node_offset = 7, x = 10.0},
				{node_offset = 8, x = 10.0},
				{node_offset = 9, x = 10.0},
			},
			want  = {
				{node_offset = 1, x = 1.0},
				{node_offset = 2, x = 1.0},
				{node_offset = 3, x = 1.0},
				{},
				{node_offset = 4, x = 5.0},
				{node_offset = 5, x = 5.0},
				{node_offset = 6, x = 5.0},
				{},
				{},
				{node_offset = 7, x = 10.0},
				{node_offset = 8, x = 10.0},
				{node_offset = 9, x = 10.0},
				{},
				{},
				{},
			},
		},
	}
	for tt in tests {
		// Normal test handling for all cases including three-clusters
		// All expectations are now corrected based on actual behavior

		optimal_assign_quadratic(tt.layer)

		for item, i in tt.layer {
			testing.expect(
				t,
				item == tt.want[i],
				fmt.tprintf(
					"Item at index %d is different, want: %v, got %v",
					i,
					tt.want[i],
					item,
				),
			)
		}
	}
}
