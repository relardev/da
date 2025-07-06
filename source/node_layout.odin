package game

import clay "clay-odin"
import hm "handle_map"

fill_node_sizes :: proc() {
	clay.BeginLayout()
	if clay.UI()(
	{
		id = clay.ID("OuterContainer"),
		layout = {
			sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
			layoutDirection = .TopToBottom,
		},
	},
	) {
		node_iter := hm.make_iter(&g.graph.nodes)
		for node in hm.iter(&node_iter) {
			if clay.UI()(
			{
				id = clay.ID("Node", node.handle.idx),
				layout = {sizing = {width = {type = .Fit}, height = {type = .Fit}}},
				custom = {customData = &node.handle},
			},
			) {
				layout_node_core(node)
			}
		}
	}
	commands := clay.EndLayout()

	for i in 0 ..< commands.length {
		command := clay.RenderCommandArray_Get(&commands, i)
		if command.commandType == .Custom {
			handle := cast(^NodeHandle)command.renderData.custom.customData
			node := hm.get(&g.graph.nodes, handle^)
			node.size_px = {command.boundingBox.width, command.boundingBox.height}
		}
	}
}
