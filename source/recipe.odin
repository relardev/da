package game

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import hm "handle_map"

clipboard_after_paste :: proc() {
	recipe_create_from_clipboard()
}

// Edge that to node might not exist yet, so we look it up after all nodes are created
// used for control nodes
FutureEdge :: struct {
	from: NodeHandle,
	to:   string,
}

recipe_create_from_clipboard :: proc() {
	hm.clear(&g.graph.nodes)
	hm.clear(&g.graph.edges)

	mem.dynamic_arena_free_all(&g.recipe_arena)
	g.recipe = new(Recipe, allocator = g.recipe_allocator)
	err := json.unmarshal(g.pasted[:g.pasted_len + 1], g.recipe, allocator = g.recipe_allocator)
	if err != nil {
		return
	}

	future_edges := make([dynamic]FutureEdge, 0, 8, allocator = g.recipe_allocator)

	for name, node_def in g.recipe.Nodes {
		arguments := make([]string, len(node_def.Args), allocator = g.recipe_allocator)
		i := 0
		for key, value in node_def.Args {
			arguments[i] = fmt.aprintf("%v: %v", key, value, allocator = g.recipe_allocator)
			i += 1
		}
		if node_def.Type == "C_IF" {
			if_handle := hm.add(
				&g.graph.nodes,
				Node{name = name, type = node_def.Type, arguments = arguments, is_if_node = true},
			)

			trues := node_def.Args["true_node_ids"].(json.Array)
			for true_node_name in trues {
				true_node_name := true_node_name.(json.String)
				append(&future_edges, FutureEdge{from = if_handle, to = true_node_name})
			}

			falses := node_def.Args["false_node_ids"].(json.Array)
			for false_node_name in falses {
				false_node_name := false_node_name.(json.String)
				append(&future_edges, FutureEdge{from = if_handle, to = false_node_name})
			}
		} else {
			hm.add(&g.graph.nodes, Node{name = name, type = node_def.Type, arguments = arguments})
		}
	}

	for future_edge in future_edges {
		node_iter := hm.make_iter(&g.graph.nodes)
		for node in hm.iter(&node_iter) {
			if node.name == future_edge.to {
				hm.add(&g.graph.edges, Edge{from = future_edge.from, to = node.handle})
				break
			}
		}
	}

	match_conditions := g.recipe.Trigger.Args["match_conditions"]
	start_args := make([]string, len(match_conditions), allocator = g.recipe_allocator)
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
			str = fmt.aprintf("%v exists", match_condition.Key, allocator = g.recipe_allocator)
		}
		start_args[i] = str
	}
	hm.add(&g.graph.nodes, Node{name = "_start", arguments = start_args})

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

	fill_node_sizes()
	graph_calculate_layout(&g.graph)
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
