package game

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:math/rand"
import "core:mem"
import gl "graph_layout"
import hm "handle_map"

RANDOM_SEED :: 0x123456789abcdef0

clipboard_after_paste :: proc() {
	recipe_create_from_pasted()
}

// Edge that to node might not exist yet, so we look it up after all nodes are created
// used for control nodes
FutureEdge :: struct {
	from: NodeHandle,
	to:   string,
}

recipe_create_from_pasted :: proc() {
	state := rand.create(RANDOM_SEED)
	context.random_generator = rand.default_random_generator(&state)
	hm.clear(&g.graph.nodes)
	hm.clear(&g.graph.edges)

	mem.dynamic_arena_free_all(&g.recipe_arena)
	g.recipe = new(Recipe, allocator = g.recipe_allocator)
	err := json.unmarshal(
		g.pasted[:g.pasted_len + 1],
		g.recipe,
		allocator = g.recipe_allocator,
	)
	if err != nil {
		log.error("Failed to unmarshal recipe: %v", err)
		return
	}

	last_attribute_id: i32 = 0

	// Start node (triggers)
	match_conditions := g.recipe.Trigger.Args["match_conditions"]
	start_args := make(
		[]Argument,
		len(match_conditions),
		allocator = g.recipe_allocator,
	)
	for match_condition, i in match_conditions {
		str: string
		if match_condition.Operator != "" {
			str = fmt.aprintf(
				"%v %v %v",
				match_condition.Key,
				match_condition.Operator,
				match_condition.Value,
				allocator = g.recipe_allocator,
			)
		} else {
			str = fmt.aprintf(
				"%v exists",
				match_condition.Key,
				allocator = g.recipe_allocator,
			)
		}
		start_args[i] = argument_create(str, &last_attribute_id)
	}
	hm.add(&g.graph.nodes, Node{name = "_start", arguments = start_args})

	// Create nodes
	future_edges := make(
		[dynamic]FutureEdge,
		0,
		8,
		allocator = g.recipe_allocator,
	)
	for name, node_def in g.recipe.Nodes {
		arguments := make(
			[]Argument,
			len(node_def.Args),
			allocator = g.recipe_allocator,
		)
		i := 0
		for key, value in node_def.Args {
			arguments[i] = argument_create(
				fmt.aprintf(
					"%v: %v",
					key,
					value,
					allocator = g.recipe_allocator,
				),
				&last_attribute_id,
			)
			i += 1
		}
		switch node_def.Type {
		case "C_IF":
			if_handle := hm.add(
				&g.graph.nodes,
				Node {
					name = name,
					type = node_def.Type,
					arguments = arguments,
					is_if_node = true,
				},
			)

			trues := node_def.Args["true_node_ids"].(json.Array)
			for true_node_name in trues {
				true_node_name := true_node_name.(json.String)
				append(
					&future_edges,
					FutureEdge{from = if_handle, to = true_node_name},
				)
			}

			falses := node_def.Args["false_node_ids"].(json.Array)
			for false_node_name in falses {
				false_node_name := false_node_name.(json.String)
				append(
					&future_edges,
					FutureEdge{from = if_handle, to = false_node_name},
				)
			}
		case "C_DELAY":
			delay := hm.add(
				&g.graph.nodes,
				Node{name = name, type = node_def.Type, arguments = arguments},
			)

			next_nodes := node_def.Args["next_node_ids"].(json.Array)
			for next_node in next_nodes {
				true_node_name := next_node.(json.String)
				append(
					&future_edges,
					FutureEdge{from = delay, to = true_node_name},
				)
			}

		case:
			hm.add(
				&g.graph.nodes,
				Node{name = name, type = node_def.Type, arguments = arguments},
			)
		}
	}

	for future_edge in future_edges {
		node_iter := hm.make_iter(&g.graph.nodes)
		for node in hm.iter(&node_iter) {
			if node.name == future_edge.to {
				hm.add(
					&g.graph.edges,
					Edge{from = future_edge.from, to = node.handle},
				)
				break
			}
		}
	}

	// Edges
	for from, tos in g.recipe.Edges {
		for to in tos {
			from_handle: NodeHandle
			to_handle: NodeHandle
			node_iter := hm.make_iter(&g.graph.nodes)
			for node in hm.iter(&node_iter) {
				if node.name == from {
					from_handle = node.handle
				}
				if node.name == to {
					to_handle = node.handle
				}
			}
			if from_handle == {} || to_handle == {} {
				panic("Failed to find node for edge")
			}
			hm.add(&g.graph.edges, Edge{from = from_handle, to = to_handle})
		}
	}

	if g.hide_noops {
		node_iter := hm.make_iter(&g.graph.nodes)
		for node in hm.iter(&node_iter) {
			if node.type == "T_NOOP" {
				// log.info("Removing noop node: %v", node.handle)
				outgoing_edges := make(
					[dynamic]NodeHandle,
					0,
					8,
					allocator = g.recipe_allocator,
				)
				edge_iter := hm.make_iter(&g.graph.edges)
				for edge in hm.iter(&edge_iter) {
					if edge.from == node.handle {
						append(&outgoing_edges, edge.to)
						// log.info("\tremoving outgoing edge: %v -> %v", edge.from, edge.to)
						hm.remove(&g.graph.edges, edge.handle)
					}
				}

				edge_iter = hm.make_iter(&g.graph.edges)
				for edge in hm.iter(&edge_iter) {
					if edge.to == node.handle {
						hm.remove(&g.graph.edges, edge.handle)
						// log.info("\tremoving incoming edge: %v -> %v", edge.from, edge.to)
						for outgoing_edge in outgoing_edges {
							// Add edges from the node to all outgoing edges
							// log.info("\tadding edge: %v -> %v", edge.from, outgoing_edge)
							hm.add(
								&g.graph.edges,
								Edge{from = edge.from, to = outgoing_edge},
							)
						}
					}
				}
				hm.remove(&g.graph.nodes, node.handle)
			}
		}
	}

	max_node_size := fill_node_sizes()

	// Calculate node and edge positions 
	{
		nodes := hm.num_used(g.graph.nodes) - 1 // exclude the zero node
		edges := hm.num_used(g.graph.edges) - 1 // exclude the zero edge

		buffer_size, alignment := gl.allocation_needed(nodes, edges)
		buffer := runtime.make_aligned(
			[]u8,
			buffer_size,
			alignment,
			allocator = g.recipe_allocator,
		)
		assert(buffer != nil, "Failed to allocate buffer for graph layout")
		gl_graph := gl.graph_new(buffer, nodes, edges)

		node_iter := hm.make_iter(&g.graph.nodes)
		for node in hm.iter(&node_iter) {
			node.size_px = max_node_size
			gl.graph_add_node(gl_graph, gl.id(node.handle), node.size_px)
		}

		edge_iter := hm.make_iter(&g.graph.edges)
		for edge in hm.iter(&edge_iter) {
			ok := gl.graph_add_edge(gl_graph, gl.id(edge.from), gl.id(edge.to))
			assert(ok, "Failed to add edge")
		}

		_, ok_layout := gl.graph_calculate_layout(gl_graph)
		assert(ok_layout, "Failed to calculate layout")

		node_iter = hm.make_iter(&g.graph.nodes)
		for node in hm.iter(&node_iter) {
			position_px, ok := gl.graph_read_node(gl_graph, gl.id(node.handle))
			assert(ok, "Failed to read node position")
			node.position_px = position_px
		}

		edge_iter = hm.make_iter(&g.graph.edges)
		for edge in hm.iter(&edge_iter) {
			result, ok := gl.graph_read_edge(
				gl_graph,
				gl.id(edge.from),
				gl.id(edge.to),
			)
			segments := make(
				[dynamic]gl.Segment,
				0,
				len(result.segments),
				allocator = g.recipe_allocator,
			)

			assert(ok, "Failed to read edge to position")
			for segment in result.segments {
				append(&segments, segment)
			}
			fmt.println("Edge from ", edge.from, " to ", edge.to)
			for segment in segments {
				fmt.println(segment.type, "\t", segment.end)
			}
			edge.segments = segments[:]
			edge.arrow_direction = result.arrow_direction
		}

		//debug stuff
		g.graph.gutters_vertical = gl_graph.gutters_vertical[:]
		g.graph.gutters_horizontal = gl_graph.gutters_horizontal[:]
	}
}

Recipe :: struct {
	Name:    string `json:"name"`,
	Enabled: bool `json:"enabled"`,
	Trigger: TriggerDefinition `json:"trigger"`,
	Readers: map[string]ReaderDefinition `json:"readers"`,
	Writers: map[string]WriterDefinition `json:"writers"`,
	Nodes:   map[string]NodeDefinition `json:"nodes"`,
	Edges:   map[string][]string `json:"edges"`,
	Type:    string `json:"type"`,
}

TriggerDefinition :: struct {
	Type: string `json:"type"`,
	Args: map[string][]TriggerDefArgs `json:"args"`,
}

TriggerDefArgs :: struct {
	Key:      string `json:"key"`,
	Value:    json.Value `json:"value"`,
	Operator: string `json:"operator"`,
}

ReaderDefinition :: struct {
	Type: string `json:"type"`,
	Args: map[string]json.Value `json:"args"`,
}

WriterDefinition :: struct {
	Type: string `json:"type" bson:"type"`,
	Args: map[string]json.Value `json:"args"`,
}

NodeDefinition :: struct {
	Type: string `json:"type"`,
	Args: map[string]json.Value `json:"args"`,
}
