package game

import "core:encoding/json"
import "core:mem"
import hm "handle_map"

clipboard_after_paste :: proc() {
	recipe_create_from_clipboard()
}

recipe_create_from_clipboard :: proc() {
	mem.dynamic_arena_free_all(&g.recipe_arena)
	g.recipe = new(Recipe, allocator = g.recipe_allocator)
	err := json.unmarshal(g.pasted[:g.pasted_len + 1], g.recipe, allocator = g.recipe_allocator)
	assert(err == nil, "Failed to parse JSON data")

	// n0 := hm.add(&g.graph.nodes, Node{text = "Node 0", size_px = {200, 200}})
	// n1 := hm.add(&g.graph.nodes, Node{text = "Node 1"})
	// n2 := hm.add(&g.graph.nodes, Node{text = "Node top2"})
	//
	// hm.add(&g.graph.edges, Edge{from = n0, to = n1})
	// hm.add(&g.graph.edges, Edge{from = n2, to = n1})


	n0 := hm.add(&g.graph.nodes, Node{text = "Node 0", size_px = {300, 200}})
	n02 := hm.add(&g.graph.nodes, Node{text = "Node 02"})
	n1 := hm.add(&g.graph.nodes, Node{text = "Node 1"})
	n2 := hm.add(&g.graph.nodes, Node{text = "Node 2"})
	n3 := hm.add(&g.graph.nodes, Node{text = "Node 3"})
	n4 := hm.add(&g.graph.nodes, Node{text = "Node 4"})
	hm.add(&g.graph.nodes, Node{text = "Node 5"})

	hm.add(&g.graph.edges, Edge{from = n0, to = n1})
	hm.add(&g.graph.edges, Edge{from = n1, to = n2})
	hm.add(&g.graph.edges, Edge{from = n0, to = n2})
	hm.add(&g.graph.edges, Edge{from = n02, to = n2})
	hm.add(&g.graph.edges, Edge{from = n0, to = n3})
	hm.add(&g.graph.edges, Edge{from = n1, to = n3})
	hm.add(&g.graph.edges, Edge{from = n2, to = n3})
	hm.add(&g.graph.edges, Edge{from = n1, to = n4})
	hm.add(&g.graph.edges, Edge{from = n4, to = n3})

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
