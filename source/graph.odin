package game

import ts "core:container/topological_sort"
import "core:log"
import hm "handle_map"

Graph :: struct {
	nodes:              hm.Handle_Map(Node, NodeHandle, 1024),
	edges:              hm.Handle_Map(Edge, EdgeHandle, 1024),
	draw_gutters:       bool,
	gutters_vertical:   [dynamic]Gutter,
	gutters_horizontal: [dynamic]Gutter,
	cell_size_px:       Vec2,
}

NodeHandle :: hm.Handle
EdgeHandle :: hm.Handle

Node :: struct {
	handle:      NodeHandle,
	text:        string,
	position:    Vec2i,
	position_px: Vec2,
	size_px:     Vec2,
	depth:       i32,
}

Edge :: struct {
	handle: EdgeHandle,
	from:   NodeHandle,
	to:     NodeHandle,
}

Gutter :: struct {
	edges:   [dynamic]EdgeHandle,
	pos:     f32,
	size_px: f32,
}

graph_calculate_layout :: proc(graph: ^Graph) {
	sorter: ts.Sorter(NodeHandle)
	main_allocator := context.allocator
	context.allocator = context.temp_allocator
	ts.init(&sorter)
	defer ts.destroy(&sorter)

	node_iter := hm.make_iter(&graph.nodes)
	for node in hm.iter(&node_iter) {
		ok := ts.add_key(&sorter, node.handle)
		assert(ok, "Failed to add node to sorter")
	}

	edge_iter := hm.make_iter(&graph.edges)
	for edge in hm.iter(&edge_iter) {
		ok := ts.add_dependency(&sorter, edge.to, edge.from)
		assert(ok, "Failed to add edge dependency to sorter")
	}

	nodes_sorted, cycled := ts.sort(&sorter)

	assert(len(cycled) == 0, "Graph contains cycles")

	layers := make(map[NodeHandle]i32, hm.num_used(graph.nodes))
	for node in nodes_sorted {
		max_prev: i32 = 0
		has_pred := false
		for u in graph_predecessors_of(graph, node) {
			has_pred = true
			if layers[u] + 1 > max_prev {
				max_prev = layers[u] + 1
			}
		}
		if has_pred {
			layers[node] = max_prev
		} else {
			layers[node] = 0
		}
	}

	y_max: i32 = 0
	for node_handle, layer in layers {
		node := hm.get(&graph.nodes, node_handle)
		node.position.y = layer
		if layer > y_max {
			y_max = layer
		}
	}

	layer_filling := make(map[i32][dynamic]NodeHandle)
	for node_handle in layers {
		node := hm.get(&graph.nodes, node_handle)
		layer := layer_filling[node.position.y]
		append(&layer, node_handle)
		layer_filling[node.position.y] = layer
	}

	x_max: i32 = 0
	for _, nodes in layer_filling {
		for node_handle, idx in nodes {
			node := hm.get(&graph.nodes, node_handle)
			node.position.x = i32(idx)
			if i32(idx) > x_max {
				x_max = i32(idx)
			}
		}
	}

	graph.gutters_vertical = make([dynamic]Gutter, x_max + 2, allocator = main_allocator)
	graph.gutters_horizontal = make([dynamic]Gutter, y_max + 2, allocator = main_allocator)

	// Calculate gutters edges
	{
		edges_iter := hm.make_iter(&graph.edges)
		for edge in hm.iter(&edges_iter) {
			from_node := hm.get(&graph.nodes, edge.from)
			to_node := hm.get(&graph.nodes, edge.to)

			if from_node.position.y + 1 == to_node.position.y &&
			   from_node.position.x == to_node.position.x {
				continue // Skip edges that are direct vertical connections
			}

			// Horizontal
			{
				horizontal := from_node.position.y + 1
				horizontal_edges := &graph.gutters_horizontal[horizontal].edges
				append(horizontal_edges, edge.handle)
			}

			// Vertical
			{
				if from_node.position.y + 1 == to_node.position.y &&
				   from_node.position.x == to_node.position.x {
					continue // dont use vertical gutter if the edges are on adjecent rows
				}

				vertical := from_node.position.x + 1
				if from_node.position.y < to_node.position.y {
					vertical = to_node.position.x
				}

				vertical_edges := &graph.gutters_vertical[vertical].edges
				append(vertical_edges, edge.handle)
			}
		}

		for &gutter in graph.gutters_vertical {
			gutter.size_px = f32(10 * len(gutter.edges))
		}

		for &gutter in graph.gutters_horizontal {
			gutter.size_px = f32(10 * len(gutter.edges))
		}
	}

	node_iter = hm.make_iter(&graph.nodes)
	for node in hm.iter(&node_iter) {
		if graph.cell_size_px.x < node.size_px.x {
			graph.cell_size_px.x = node.size_px.x
		}
		if graph.cell_size_px.y < node.size_px.y {
			graph.cell_size_px.y = node.size_px.y
		}
	}

	// Fill gutter positions
	{
		previous_width: f32 = 0
		for &gutter in graph.gutters_vertical {
			gutter.pos = previous_width
			previous_width += gutter.size_px + graph.cell_size_px.x
		}

		previous_height: f32 = 0
		for &gutter in graph.gutters_horizontal {
			gutter.pos = previous_height
			previous_height += gutter.size_px + graph.cell_size_px.y
		}
	}

	log.info("max node size px:", graph.cell_size_px)

	node_iter = hm.make_iter(&graph.nodes)
	for node in hm.iter(&node_iter) {
		node.size_px = graph.cell_size_px
		node.position_px = graph_get_node_position_px(graph, node.position)
	}
}

graph_get_node_position_px :: proc(graph: ^Graph, node_pos: Vec2i) -> Vec2 {
	// Width:
	width: f32 = 0.0
	for gutter, i in graph.gutters_vertical {
		if i32(i) == node_pos.x {
			width += gutter.size_px
			break
		}
		width += gutter.size_px + graph.cell_size_px.x
	}

	height: f32 = 0.0
	for gutter, i in graph.gutters_horizontal {
		if i32(i) == node_pos.y {
			height += gutter.size_px
			break
		}
		height += gutter.size_px + graph.cell_size_px.y
	}
	return {width, height}
}

graph_predecessors_of :: proc(graph: ^Graph, node: NodeHandle) -> []NodeHandle {
	edges_iter := hm.make_iter(&graph.edges)
	preds := make([dynamic]NodeHandle, 0, 16)
	for edge in hm.iter(&edges_iter) {
		if edge.to == node {
			append(&preds, edge.from)
		}
	}
	return preds[:]
}

graph_close :: proc(graph: ^Graph) {
	for gutter in graph.gutters_vertical {
		delete(gutter.edges)
	}
	delete(graph.gutters_vertical)

	for gutter in graph.gutters_horizontal {
		delete(gutter.edges)
	}
	delete(graph.gutters_horizontal)
}

graph_print_gutter :: proc(graph: ^Graph) {
	for gutter, i in graph.gutters_vertical {
		for edge_handle in gutter.edges {
			edge := hm.get(&graph.edges, edge_handle)
			from_node := hm.get(&graph.nodes, edge.from)
			to_node := hm.get(&graph.nodes, edge.to)
			log.info(i, edge_handle, from_node.text, "->", to_node.text)
		}
	}

	for gutter, i in graph.gutters_horizontal {
		for edge_handle in gutter.edges {
			edge := hm.get(&graph.edges, edge_handle)
			from_node := hm.get(&graph.nodes, edge.from)
			to_node := hm.get(&graph.nodes, edge.to)
			log.info(i, edge_handle, from_node.text, "->", to_node.text)
		}
	}

}
