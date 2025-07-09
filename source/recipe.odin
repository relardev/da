package game

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import hm "handle_map"

clipboard_after_paste :: proc() {
	recipe_create_from_clipboard()
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

	// n0 := hm.add(&g.graph.nodes, Node{text = "Node 0", size_px = {200, 200}})
	// n1 := hm.add(&g.graph.nodes, Node{text = "Node 1"})
	// n2 := hm.add(&g.graph.nodes, Node{text = "Node top2"})
	//
	// hm.add(&g.graph.edges, Edge{from = n0, to = n1})
	// hm.add(&g.graph.edges, Edge{from = n2, to = n1})


	for name, node_def in g.recipe.Nodes {
		arguments := make([]string, len(node_def.Args), allocator = g.recipe_allocator)
		i := 0
		for key, value in node_def.Args {
			arguments[i] = fmt.aprintf("%v: %v", key, value, allocator = g.recipe_allocator)
			i += 1
		}
		hm.add(&g.graph.nodes, Node{text = name, type = node_def.Type, arguments = arguments})
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
	hm.add(&g.graph.nodes, Node{text = "_start", arguments = start_args})

	for from, tos in g.recipe.Edges {
		for to in tos {
			from_handle: NodeHandle
			to_handle: NodeHandle
			node_iter := hm.make_iter(&g.graph.nodes)
			for node in hm.iter(&node_iter) {
				if node.text == from {
					from_handle = node.handle
				}
				if node.text == to {
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
