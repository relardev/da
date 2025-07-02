package game

import hm "handle_map"

Graph :: struct {
	nodes: hm.Handle_Map(Node, NodeHandle, 1024),
}

NodeHandle :: hm.Handle

Node :: struct {
	handle:   NodeHandle,
	text:     string,
	position: Vec2,
	width:    f32,
	height:   f32,
	edges:    []NodeHandle,
}
