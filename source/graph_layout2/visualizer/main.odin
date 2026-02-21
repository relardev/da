package graph_viz

import gl2 "../"
import gl "../../graph_layout/"
import "base:runtime"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

_ :: gl
_ :: gl2

V2 :: [2]f32

DEBUG_SECTION_START :: V2{1000, 0}
DebugDrawSectionOrigin := DEBUG_SECTION_START

DEBUG_PADDING :: 5
DebugDrawMaxY: f32 = 0

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
	nodes:    []Node,
	edges:    []Edge,
	y_offset: f32,
}

main :: proc() {
	rl.InitWindow(2000, 1200, "graph viz")
	max_node_size := V2{50, 50}

	graphs := make([dynamic][2]Graph, 0)

	add_graph_wide_pyramid(&graphs)
	add_graph_inverted_pyramid(&graphs)
	add_graph_pyramid(&graphs)
	add_graph3(&graphs)
	add_graph1(&graphs)
	add_graph2(&graphs)

	graph_selector := 0
	run_gl_layout := true // Run on first frame

	for !rl.WindowShouldClose() {
		if rl.IsKeyPressed(.T) {
			graph_selector = (graph_selector + 1) % len(graphs)
			run_gl_layout = true
		}

		if rl.IsKeyPressed(.N) {
			run_gl_layout = true
		}

		graph_pair := &graphs[graph_selector]
		graph_1 := &graph_pair[0]
		graph_2 := &graph_pair[1]

		rl.BeginDrawing()

		DebugDrawSectionOrigin = DEBUG_SECTION_START + V2{0, graph_2.y_offset}
		DebugDrawMaxY = 0

		if run_gl_layout {
			run_gl_layout = false
			g := graph_1
			gl_buffer := runtime.make_aligned([]u8, 64 * 1024 * 1024, 64)
			gl_graph := gl.graph_new(
				gl_buffer,
				len(g.nodes),
				len(g.edges),
				gutter_edge_distance = 10,
				gutter_padding = 20,
			)
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
			debug_draw_rect :: proc(
				pos: V2,
				size: V2,
				color: [4]u8,
				text: string,
			) {
				orig := DebugDrawSectionOrigin
				upper_left := orig + pos + DEBUG_PADDING
				rl.DrawRectangleV(upper_left, size, transmute(rl.Color)color)
				rl.DrawText(
					strings.clone_to_cstring(text),
					i32(upper_left.x) + 5,
					i32(upper_left.y) + 5,
					20,
					rl.WHITE,
				)

				DebugDrawMaxY = max(
					DebugDrawMaxY,
					pos[1] + size[1] + DEBUG_PADDING,
				)
			}

			debug_section :: proc(name: string) {
				DebugDrawSectionOrigin =
					DebugDrawSectionOrigin +
					V2{0, DebugDrawMaxY + DEBUG_PADDING}
				DebugDrawMaxY = 0
				orig := DebugDrawSectionOrigin

				rl.DrawText(
					strings.clone_to_cstring(name),
					i32(orig.x),
					i32(orig.y - 30),
					30,
					rl.BLACK,
				)
				rl.DrawLineV(orig, orig + V2{1200, 0}, rl.BLACK)
			}

			g := graph_2
			graph: gl2.Graph
			gl2.graph_init(
				&graph,
				u16(len(g.nodes)),
				u16(len(g.edges)),
				max_node_size,
				context.allocator,
				debug_draw_rect = debug_draw_rect,
				debug_new_section = debug_section,
				node_spacing = 75,
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

graph_fill :: proc(
	graphs: ^[dynamic][2]Graph,
	nodes: []Node,
	edges: []Edge,
	y_offset: f32 = 0,
) {
	nodes_gl := make([]Node, len(nodes))
	copy_slice(nodes_gl, nodes[:])

	edges_gl := make([]Edge, len(edges))
	copy_slice(edges_gl, edges[:])

	graph_gl := Graph {
		nodes    = nodes_gl[:],
		edges    = edges_gl[:],
		y_offset = y_offset,
	}

	nodes_gl2 := make([]Node, len(nodes))
	copy_slice(nodes_gl2, nodes[:])

	edges_gl2 := make([]Edge, len(edges))
	copy_slice(edges_gl2, edges[:])

	graph_gl2 := Graph {
		nodes    = nodes_gl2[:],
		edges    = edges_gl2[:],
		y_offset = y_offset,
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

	graph_fill(graphs, nodes[:], edges[:], 300)
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

	graph_fill(graphs, nodes[:], edges[:], 600)
}

add_graph3 :: proc(graphs: ^[dynamic][2]Graph) {
	nodes := [?]Node {
		{id = 1},
		{id = 2},
		{id = 3},
		{id = 5},
		{id = 6},
		{id = 7},
		{id = 8},
		{id = 9},
	}
	edges := [?]Edge {
		{from = 1, to = 2},
		{from = 2, to = 3},
		{from = 5, to = 6},
		{from = 7, to = 8},
		{from = 8, to = 9},
	}

	graph_fill(graphs, nodes[:], edges[:], 400)
}

add_graph_inverted_pyramid :: proc(graphs: ^[dynamic][2]Graph) {
	nodes := [?]Node {
		// Layer 0: 5 nodes
		{id = 0},
		{id = 1},
		{id = 2},
		{id = 3},
		{id = 4},
		// Layer 1: 3 nodes
		{id = 5},
		{id = 6},
		{id = 7},
		// Layer 2: 1 node
		{id = 8},
	}
	edges := [?]Edge {
		// Layer 0 -> Layer 1
		{from = 0, to = 5},
		{from = 1, to = 5},
		{from = 2, to = 6},
		{from = 3, to = 7},
		{from = 4, to = 7},
		// Layer 1 -> Layer 2
		{from = 5, to = 8},
		{from = 6, to = 8},
		{from = 7, to = 8},
	}

	graph_fill(graphs, nodes[:], edges[:], 400)
}

add_graph_pyramid :: proc(graphs: ^[dynamic][2]Graph) {
	nodes := [?]Node {
		// Layer 0: 1 node
		{id = 0},
		// Layer 1: 3 nodes
		{id = 1},
		{id = 2},
		{id = 3},
		// Layer 2: 5 nodes
		{id = 4},
		{id = 5},
		{id = 6},
		{id = 7},
		{id = 8},
	}
	edges := [?]Edge {
		// Layer 0 -> Layer 1
		{from = 0, to = 1},
		{from = 0, to = 2},
		{from = 0, to = 3},
		// Layer 1 -> Layer 2
		{from = 1, to = 4},
		{from = 1, to = 5},
		{from = 2, to = 6},
		{from = 3, to = 7},
		{from = 3, to = 8},
	}

	graph_fill(graphs, nodes[:], edges[:], 400)
}

add_graph_wide_pyramid :: proc(graphs: ^[dynamic][2]Graph) {
	nodes := [?]Node {
		// Layer 0: 1 node
		{id = 0},
		// Layer 1: 5 nodes
		{id = 1},
		{id = 2},
		{id = 3},
		{id = 4},
		{id = 5},
		// Layer 2: 11 nodes
		{id = 6},
		{id = 7},
		{id = 8},
		{id = 9},
		{id = 10},
		{id = 11},
		{id = 12},
		{id = 13},
		{id = 14},
		{id = 15},
		{id = 16},
	}
	edges := [?]Edge {
		// Layer 0 -> Layer 1
		{from = 0, to = 1},
		{from = 0, to = 2},
		{from = 0, to = 3},
		{from = 0, to = 4},
		{from = 0, to = 5},
		// Layer 1 -> Layer 2
		{from = 1, to = 6},
		{from = 1, to = 7},
		{from = 2, to = 8},
		{from = 2, to = 9},
		{from = 3, to = 10},
		{from = 3, to = 11},
		{from = 4, to = 12},
		{from = 4, to = 13},
		{from = 5, to = 14},
		{from = 5, to = 15},
		{from = 5, to = 16},
	}

	graph_fill(graphs, nodes[:], edges[:], 400)
}
