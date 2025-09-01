package graph_layout

import "core:fmt"
import "core:mem"
import "core:testing"

@(test)
test_allocation_needed_constant_memory :: proc(t: ^testing.T) {
	tests := []struct {
		name: string,
		nodes: int,
		edges: int,
		expected_size: int,
		expected_alignment: int,
	}{
		{
			name = "Small graph (10 nodes, 15 edges)",
			nodes = 10,
			edges = 15,
			expected_size = 10356,
			expected_alignment = 64,
		},
		{
			name = "Medium graph (50 nodes, 100 edges)",
			nodes = 50,
			edges = 100,
			expected_size = 61168,
			expected_alignment = 64,
		},
		{
			name = "Large graph (100 nodes, 200 edges)",
			nodes = 100,
			edges = 200,
			expected_size = 131248,
			expected_alignment = 64,
		},
	}

	for tt in tests {
		size, alignment := allocation_needed(tt.nodes, tt.edges)
		
		testing.expect(
			t, 
			size == tt.expected_size,
			fmt.tprintf(
				"[%s] Memory size changed: expected %d, got %d",
				tt.name,
				tt.expected_size,
				size,
			),
		)
		
		testing.expect(
			t,
			alignment == tt.expected_alignment,
			fmt.tprintf(
				"[%s] Memory alignment changed: expected %d, got %d",
				tt.name,
				tt.expected_alignment,
				alignment,
			),
		)
	}
}

@(test)
test_optimal_assign_quadratic_allocation_needed_constant_memory :: proc(t: ^testing.T) {
	tests := []struct {
		name: string,
		n: int,
		expected_bytes: int,
		expected_alignment: int,
	}{
		{
			name = "Empty layer",
			n = 0,
			expected_bytes = 0,
			expected_alignment = 64,
		},
		{
			name = "Small layer (5 cells)",
			n = 5,
			expected_bytes = 256,
			expected_alignment = 64,
		},
		{
			name = "Medium layer (20 cells)",
			n = 20,
			expected_bytes = 1600,
			expected_alignment = 64,
		},
		{
			name = "Large layer (50 cells)",
			n = 50,
			expected_bytes = 7000,
			expected_alignment = 64,
		},
	}

	for tt in tests {
		bytes, alignment := optimal_assign_quadratic_allocation_needed(tt.n)
		
		testing.expect(
			t,
			bytes == tt.expected_bytes,
			fmt.tprintf(
				"[%s] Memory bytes changed: expected %d, got %d",
				tt.name,
				tt.expected_bytes,
				bytes,
			),
		)
		
		testing.expect(
			t,
			alignment == tt.expected_alignment,
			fmt.tprintf(
				"[%s] Memory alignment changed: expected %d, got %d",
				tt.name,
				tt.expected_alignment,
				alignment,
			),
		)
	}
}