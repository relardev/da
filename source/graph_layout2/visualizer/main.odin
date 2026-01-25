package graph_viz

import gl2 "../"
import gl "../../graph_layout/"
import "base:runtime"
import rl "vendor:raylib"

_ :: gl
_ :: gl2

V2 :: [2]f32


Node :: struct {
	id:  int,
	rec: rl.Rectangle,
}

Edge :: struct {
	from: int,
	to:   int,
}

Graph :: struct {
	nodes: []Node,
	edges: []Edge,
}

main :: proc() {
	rl.InitWindow(2000, 1200, "graph viz")

	nodes := [?]Node{{id = 0}, {id = 1}}
	edges := [?]Edge{{from = 0, to = 1}}
	all_nodes_size := V2{50, 50}

	nodes_gl := [len(nodes)]Node{}
	edges_gl := [len(edges)]Edge{}
	graph_gl := Graph {
		nodes = nodes_gl[:],
		edges = edges_gl[:],
	}

	nodes_gl2 := [len(nodes)]Node{}
	edges_gl2 := [len(edges)]Edge{}
	graph_gl2 := Graph {
		nodes = nodes_gl2[:],
		edges = edges_gl2[:],
	}

	{
		gl_buffer := runtime.make_aligned([]u8, 64 * 1024 * 1024, 64)
		gl_graph := gl.graph_new(gl_buffer, len(nodes), len(edges))
		for i: int = 0; i < len(nodes); i += 1 {
			gl.graph_add_node(gl_graph, u64(nodes[i].id), all_nodes_size)
		}
		for i: int = 0; i < len(edges); i += 1 {
			gl.graph_add_edge(gl_graph, u64(edges[i].from), u64(edges[i].to))
		}

		size, ok := gl.graph_calculate_layout(gl_graph)
		if !ok {
			panic("layout failed")
		}

		for node, i in nodes {
			pos, ok := gl.graph_read_node(gl_graph, u64(node.id))
			assert(ok)
			rec := rl.Rectangle {
				pos[0],
				pos[1],
				all_nodes_size[0],
				all_nodes_size[1],
			}

			nodes_gl[i] = {
				id  = node.id,
				rec = rec,
			}
		}
	}

	{
		graph: gl2.Graph
		gl2.graph_init(
			&graph,
			len(nodes),
			len(edges),
			all_nodes_size,
			context.allocator,
		)

		for node in nodes {
			gl2.graph_node_add(&graph, u64(node.id))
		}

		for edge in edges {
			gl2.graph_edge_add(&graph, u64(edge.from), u64(edge.to))
		}

		gl2.graph_layout_compute(&graph)

		for node, i in nodes {
			pos, ok := gl2.graph_node_read(&graph, u64(node.id))
			assert(ok)

			rec := rl.Rectangle {
				pos[0],
				pos[1],
				all_nodes_size[0],
				all_nodes_size[1],
			}

			nodes_gl2[i] = {
				id  = node.id,
				rec = rec,
			}
		}
	}

	rl.BeginDrawing()
	draw(&graph_gl, &graph_gl2)
	rl.EndDrawing()
	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		if rl.IsKeyPressed(.SPACE) {
			draw(&graph_gl, &graph_gl2)
		}
		rl.EndDrawing()
	}
}

draw :: proc(g1: ^Graph, g2: ^Graph) {
	rl.ClearBackground(rl.WHITE)
	draw_graph(g1)
	rl.DrawLine(1000, 0, 1000, 1200, rl.RED)
	draw_graph(g2, start_width = 1000)
}

draw_graph :: proc(g: ^Graph, start_width: f32 = 0) {
	for node in g.nodes {
		rec := node.rec
		rec.x += start_width
		rl.DrawRectangleRec(rec, rl.BLUE)
	}
}
