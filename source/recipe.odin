package game

import "core:encoding/json"
import "core:log"

clipboard_after_paste :: proc() {
	recipe: Recipe
	err := json.unmarshal(g.pasted[:g.pasted_len + 1], &recipe)
	assert(err == nil, "Failed to parse JSON data")
	log.info("Recipe Name: ", recipe.Name)
}

Recipe :: struct {
	Name:      string `json:"name"`,
	Enabled:   bool `json:"enabled"`,
	PartnerID: string `json:"partner_id"`,
	Trigger:   TriggerDefinition `json:"trigger"`,
	Readers:   map[string]ReaderDefinition `json:"readers"`,
	Writers:   map[string]WriterDefinition `json:"writers"`,
	Nodes:     map[string]NodeDefinition `json:"nodes"`,
	Edges:     map[string][]string `json:"edges"`,
	Type:      string `json:"type"`,
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
