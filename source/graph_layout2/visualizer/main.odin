package graph_viz

import gl2 "../"
import gl "../../graph_layout/"
import "base:runtime"
import "core:fmt"
import rl "vendor:raylib"

_ :: gl
_ :: gl2

V2 :: [2]f32


Node :: struct {
	id:  int,
	rec: rl.Rectangle,
}


Edge :: struct {
	from:     int,
	to:       int,
	start:    V2,
	segments: []Segment,
}

Segment :: struct {
	end:  V2,
	type: SegmentType,
}

SegmentType :: enum {
	line,
	bridge,
}

Graph :: struct {
	nodes: []Node,
	edges: []Edge,
}

main :: proc() {
	rl.InitWindow(2000, 1200, "graph viz")
	max_node_size := V2{100, 50}

	graphs := make([dynamic][2]Graph, 0)

	add_graph1(&graphs)
	add_graph2(&graphs)

	graph_selector := 0

	for !rl.WindowShouldClose() {
		if rl.IsKeyPressed(.T) {
			graph_selector = (graph_selector + 1) % len(graphs)
		}

		graph_pair := &graphs[graph_selector]
		graph_1 := &graph_pair[0]
		graph_2 := &graph_pair[1]

		{
			g := graph_1
			gl_buffer := runtime.make_aligned([]u8, 64 * 1024 * 1024, 64)
			gl_graph := gl.graph_new(gl_buffer, len(g.nodes), len(g.edges))
			for i: int = 0; i < len(g.nodes); i += 1 {
				gl.graph_add_node(gl_graph, u64(g.nodes[i].id), max_node_size)
			}
			for i: int = 0; i < len(g.edges); i += 1 {
				gl.graph_add_edge(
					gl_graph,
					u64(g.edges[i].from),
					u64(g.edges[i].to),
				)
			}

			size, ok := gl.graph_calculate_layout(gl_graph)
			if !ok {
				panic("layout failed")
			}

			for node, i in g.nodes {
				pos, ok := gl.graph_read_node(gl_graph, u64(node.id))
				assert(ok)
				rec := rl.Rectangle {
					pos[0],
					pos[1],
					max_node_size[0],
					max_node_size[1],
				}

				g.nodes[i] = {
					id  = node.id,
					rec = rec,
				}
			}

			for edge, i in g.edges {
				res, ok := gl.graph_read_edge(
					gl_graph,
					u64(edge.from),
					u64(edge.to),
				)
				assert(ok)

				my_segments := make([dynamic]Segment, 0, len(res.segments))
				for segment in res.segments {
					my_type: SegmentType
					switch segment.type {
					case .Point:
						my_type = .line
					case .Bridge:
						my_type = .bridge
					case:
						panic("unknown segment type")
					}

					append(
						&my_segments,
						Segment {
							end = segment.end,
							type = SegmentType(segment.type),
						},
					)
				}

				g.edges[i] = Edge {
					from     = edge.from,
					to       = edge.to,
					start    = my_segments[0].end,
					segments = my_segments[1:],
				}
			}
		}

		{
			g := graph_2
			graph: gl2.Graph
			gl2.graph_init(
				&graph,
				u16(len(g.nodes)),
				u16(len(g.edges)),
				max_node_size,
				context.allocator,
			)

			for node in g.nodes {
				ok := gl2.graph_node_add(&graph, u64(node.id))
				assert(ok)
			}

			for edge in g.edges {
				ok := gl2.graph_edge_add(&graph, u64(edge.from), u64(edge.to))
				assert(ok)
			}

			gl2.graph_layout_compute(&graph)

			for node, i in g.nodes {
				pos, ok := gl2.graph_node_read(&graph, u64(node.id))
				assert(ok)

				rec := rl.Rectangle {
					pos[0],
					pos[1],
					max_node_size[0],
					max_node_size[1],
				}

				g.nodes[i] = {
					id  = node.id,
					rec = rec,
				}
			}

			for edge, i in g.edges {
				res, ok := gl2.graph_edge_read(
					&graph,
					u64(edge.from),
					u64(edge.to),
				)

				assert(ok)

				segments := make([dynamic]Segment, 0)
				for {
					seg := gl2.graph_segment_read(&graph, res.segment)
					if seg == {} {
						break
					}

					seg_type: SegmentType
					switch seg.type {
					case .Line:
						seg_type = .line
					case .Bridge:
						seg_type = .bridge
					case:
						panic("unknown segment type")
					}

					append(
						&segments,
						Segment{end = seg.end, type = SegmentType(seg.type)},
					)

				}

				g.edges[i] = Edge {
					from     = edge.from,
					to       = edge.to,
					start    = res.start,
					segments = segments[:],
				}
			}
		}

		rl.BeginDrawing()
		draw(graph_pair)
		rl.EndDrawing()
	}
}

draw :: proc(gs: ^[2]Graph) {
	rl.ClearBackground(rl.WHITE)
	draw_graph(&gs[0])
	rl.DrawLine(1000, 0, 1000, 1200, rl.RED)
	draw_graph(&gs[1], start_width = 1000)
}

draw_graph :: proc(g: ^Graph, start_width: f32 = 0) {
	for node in g.nodes {
		rec := node.rec
		rec.x += start_width
		rl.DrawRectangleRec(rec, rl.BLUE)

		rl.DrawText(
			fmt.ctprintf("%d", node.id),
			i32(rec.x + rec.width / 4),
			i32(rec.y + rec.height / 4),
			20,
			rl.WHITE,
		)
	}

	for edge in g.edges {
		last := edge.start
		for segment in edge.segments {
			color := rl.BLACK
			if segment.type == .bridge {
				color = rl.RED
			}
			rl.DrawLineV(last, segment.end, color)
			last = segment.end
		}
	}
}

graph_fill :: proc(graphs: ^[dynamic][2]Graph, nodes: []Node, edges: []Edge) {
	nodes_gl := make([]Node, len(nodes))
	copy_slice(nodes_gl, nodes[:])

	edges_gl := make([]Edge, len(edges))
	copy_slice(edges_gl, edges[:])

	graph_gl := Graph {
		nodes = nodes_gl[:],
		edges = edges_gl[:],
	}

	nodes_gl2 := make([]Node, len(nodes))
	copy_slice(nodes_gl2, nodes[:])

	edges_gl2 := make([]Edge, len(edges))
	copy_slice(edges_gl2, edges[:])

	graph_gl2 := Graph {
		nodes = nodes_gl2[:],
		edges = edges_gl2[:],
	}
	append(graphs, [2]Graph{graph_gl, graph_gl2})
}

add_graph1 :: proc(graphs: ^[dynamic][2]Graph) {
	nodes := [?]Node{{id = 4}, {id = 3}, {id = 2}, {id = 1}}
	edges := [?]Edge {
		{from = 1, to = 4},
		{from = 2, to = 3},
		{from = 1, to = 3},
		{from = 2, to = 4},
	}

	graph_fill(graphs, nodes[:], edges[:])
}

add_graph2 :: proc(graphs: ^[dynamic][2]Graph) {
	nodes := [?]Node{{id = 34}, {id = 23}, {id = 12}, {id = 41}}
	edges := [?]Edge {
		{from = 23, to = 34},
		{from = 34, to = 41},
		{from = 12, to = 23},
	}
	//{id = 23},
	//{id = 34},
	//{id = 12},
	//{id = 41}

	graph_fill(graphs, nodes[:], edges[:])
}
