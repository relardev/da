#+feature dynamic-literals
package graph_layout

import "core:fmt"
import "core:testing"

@(test)
test_optimal_assign_quadratic :: proc(t: ^testing.T) {
	tests: []struct {
		name:   string,
		layer: []LayerCell,
		want:   []LayerCell,
	} = {
		{
			name="Test 1",
			layer = {
				{node_offset=2, x=0.5},
				{node_offset=1, x=1.9},
				{},
			},
			want = {
				{node_offset=2, x=0.5},
				{},
				{node_offset=1, x=1.9},
			},
		},
	}
	for tt in tests {
		optimal_assign_quadratic(tt.layer)
		for item, i in tt.layer {
			testing.expect(t, item == tt.want[i], fmt.tprintf("Item at index %d is different, want: %v, got %v", i, tt.want[i], item))
		}
	}
}

buggy_sum_proc :: proc(m: map[int]int) -> int {
	count := 0

	for k, v in m {
		if k > 1 && count == 3 {
			continue
		}
		count += v
	}
	return count
}
