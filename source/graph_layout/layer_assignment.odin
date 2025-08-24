package graph_layout

// Collect non-empty cells.
Item :: struct {
	cell: LayerCell,
}

optimal_assign_quadratic_allocation_needed :: proc(
	n: int,
) -> (
	bytes: int,
	alignment: int,
) {
	// TODO
	return 200000, 64
}

optimal_assign_quadratic :: proc(
	layer: []LayerCell,
	allocator := context.allocator,
) {
	n := len(layer)
	if n == 0 {
		return
	}

	// Collect non-empty items (they are already in x-sorted order per your guarantee).
	items, err := make([dynamic]LayerCell, 0, n, allocator = allocator)
	if err != nil {
		panic("optimal_assign_quadratic: allocation failed")
	}
	for c in layer {
		if c.node_offset != NodeOffset(0) {
			append(&items, c)
		}
	}
	m := len(items)

	// Trivial cases
	if m == 0 {
		for i in 0 ..< n {
			layer[i] = LayerCell{}
		}
		return
	}
	if m == 1 {
		best := int(items[0].x + 0.5)
		if best < 0 {best = 0}
		if best >= n {best = n - 1}
		for i in 0 ..< n {
			layer[i] = LayerCell{}
		}
		layer[best] = items[0]
		return
	}
	if m == n {
		// Already fully occupied: keep order (already sorted).
		idx := 0
		for i in 0 ..< n {
			if layer[i].node_offset != NodeOffset(0) {
				layer[idx] = layer[i]
				idx += 1
			}
		}
		return
	}

	INF := f32(3.4e38)
	dp_curr, err3 := make([]f32, n, allocator = allocator)
	if err3 != nil {
		panic("optimal_assign_quadratic: allocation failed for dp_curr")
	}

	prev_index, err4 := make([][]i16, m, allocator = allocator)
	if err4 != nil {
		panic("optimal_assign_quadratic: allocation failed for prev_index")
	}
	for k in 0 ..< m {
		prev_index[k], err = make([]i16, n, allocator = allocator)
		if err != nil {
			panic(
				"optimal_assign_quadratic: allocation failed for prev_index[k]",
			)
		}
		for j in 0 ..< n {
			prev_index[k][j] = -1
		}
	}

	dp_prev, err2 := make([]f32, n, allocator = allocator)
	if err2 != nil {
		panic("optimal_assign_quadratic: allocation failed for dp_prev")
	}
	for j in 0 ..< n {
		dp_prev[j] = INF
	}

	upper0 := n - (m - 1)
	if upper0 > n - 1 {upper0 = n - 1}
	x0 := items[0].x
	for j in 0 ..= upper0 {
		d := f32(j) - x0
		dp_prev[j] = d * d
	}

	// Transitions
	for k in 1 ..< m {
		for j in 0 ..< n {
			dp_curr[j] = INF
		}

		j_min := k
		j_max := n - (m - 1 - k)
		if j_max > n - 1 {j_max = n - 1}

		prev_min := k - 1
		prev_max := n - (m - 1 - (k - 1))
		if prev_max > n - 1 {prev_max = n - 1}

		xk := items[k].x
		best_cost := INF
		best_idx := -1

		for j in j_min ..= j_max {
			prev_candidate := j - 1
			if prev_candidate >= prev_min && prev_candidate <= prev_max {
				cost_cand := dp_prev[prev_candidate]
				if cost_cand < best_cost {
					best_cost = cost_cand
					best_idx = prev_candidate
				}
			}
			if best_idx >= 0 {
				d := f32(j) - xk
				dp_curr[j] = best_cost + d * d
				prev_index[k][j] = i16(best_idx)
			}
		}

		for j in 0 ..< n {
			dp_prev[j] = dp_curr[j]
		}
	}

	// Terminal choice
	k_last := m - 1
	best_final_cost := INF
	best_final_j := -1
	term_min := k_last
	term_max := n - 1
	for j in term_min ..= term_max {
		c := dp_prev[j]
		if c < best_final_cost {
			best_final_cost = c
			best_final_j = j
		}
	}

	// Backtrack
	slots, err6 := make([]int, m, allocator = allocator)
	if err6 != nil {
		panic("optimal_assign_quadratic: allocation failed for slots")
	}
	j := best_final_j
	for k := k_last; k >= 0; k -= 1 {
		slots[k] = j
		if k > 0 {
			j = int(prev_index[k][j])
		}
	}

	// Rebuild layer
	for i in 0 ..< n {
		layer[i] = LayerCell{}
	}
	for k in 0 ..< m {
		layer[slots[k]] = items[k]
	}
}
