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

	for !rl.WindowShouldClose() {
		nodes := [?]Node{{id = 4}, {id = 3}, {id = 2}, {id = 1}}
		edges := [?]Edge {
			{from = 1, to = 4},
			{from = 2, to = 3},
			{from = 1, to = 3},
			{from = 2, to = 4},
		}
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
				gl.graph_add_edge(
					gl_graph,
					u64(edges[i].from),
					u64(edges[i].to),
				)
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

			for edge, i in edges {
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

				edges_gl[i] = Edge {
					from     = edge.from,
					to       = edge.to,
					start    = my_segments[0].end,
					segments = my_segments[1:],
				}

				fmt.println(res)
				fmt.printf("edge gl: %v\n", edges_gl[i])
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
				ok := gl2.graph_node_add(&graph, u64(node.id))
				assert(ok)
			}

			for edge in edges {
				ok := gl2.graph_edge_add(&graph, u64(edge.from), u64(edge.to))
				assert(ok)
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

			for edge, i in edges {
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

				edges_gl2[i] = Edge {
					from     = edge.from,
					to       = edge.to,
					start    = res.start,
					segments = segments[:],
				}
			}
		}

		rl.BeginDrawing()
		draw(&graph_gl, &graph_gl2)
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
