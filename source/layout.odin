package game

import clay "clay-odin"
import hm "handle_map"


COLOR_MODIFIER := clay.Color{20, 20, 20, 0}
WHITE := clay.Color{255, 255, 255, 255}
BLACK := clay.Color{0, 0, 0, 255}

CHARCOAL := clay.Color{38, 70, 83, 255}
CHARCOAL_H := CHARCOAL + COLOR_MODIFIER
CHARCOAL_L := CHARCOAL - COLOR_MODIFIER

PERSIAN_GREEN := clay.Color{42, 157, 143, 255}
PERSIAN_GREEN_H := PERSIAN_GREEN + COLOR_MODIFIER
PERSIAN_GREEN_L := PERSIAN_GREEN - COLOR_MODIFIER

SAFFRON := clay.Color{233, 196, 106, 255}
SAFFRON_H := SAFFRON + COLOR_MODIFIER
SAFFRON_L := SAFFRON - COLOR_MODIFIER

SANDY_BROWN := clay.Color{244, 162, 97, 255}
SANDY_BROWN_H := SANDY_BROWN + COLOR_MODIFIER
SANDY_BROWN_L := SANDY_BROWN - COLOR_MODIFIER

BURNT_SIENNA := clay.Color{231, 111, 81, 255}
BURNT_SIENNA_H := BURNT_SIENNA + COLOR_MODIFIER
BURNT_SIENNA_L := BURNT_SIENNA - COLOR_MODIFIER


COLOR_BACKGROUND := CHARCOAL
COLOR_BACKGROUND_H := CHARCOAL_H
COLOR_BACKGROUND_L := CHARCOAL_L

COLOR_NODE_BORDER := BURNT_SIENNA
COLOR_NODE_BORDER_H := WHITE
COLOR_NODE_BORDER_L := BURNT_SIENNA_L

COLOR_NODE_BACKGROUND := PERSIAN_GREEN
COLOR_NODE_BACKGROUND_H := PERSIAN_GREEN_H
COLOR_NODE_BACKGROUND_L := PERSIAN_GREEN_L

COLOR_EDITOR_BACKGROUND := CHARCOAL

COLOR_EDGE := BURNT_SIENNA
COLOR_EDGE_H := WHITE
COLOR_EDGE_L := BURNT_SIENNA_L

sidebar_item_layout := clay.LayoutConfig {
	sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(50)},
	childAlignment = {y = .Center},
	padding = {8, 8, 0, 0},
}

block_type :: enum {
	Trigger,
	Conditions,
	Actions,
}

block_type_name := [block_type]string {
	.Trigger    = "Trigger",
	.Conditions = "Conditions",
	.Actions    = "Actions",
}

sidebar_item_component :: proc(bt: block_type) {
	label := block_type_name[bt]
	if clay.UI()(
	{
		id = clay.ID("SidebarBlob", u32(bt)),
		layout = sidebar_item_layout,
		backgroundColor = COLOR_BACKGROUND_H,
	},
	) {
		clay.TextDynamic(
			label,
			clay.TextConfig({textColor = BLACK, fontSize = 16, fontId = FONT_ID_TITLE_16}),
		)
	}
}

button_component :: proc(id: clay.ElementId, $text: string) {
	if clay.UI()(
	{
		id = id,
		layout = {
			padding = {8, 8, 0, 0},
			sizing = {width = clay.SizingFit({}), height = clay.SizingGrow({})},
			childAlignment = {y = .Center},
		},
		backgroundColor = COLOR_BACKGROUND,
	},
	) {
		clay.Text(
			text,
			clay.TextConfig({textColor = BLACK, fontSize = 16, fontId = FONT_ID_TITLE_16}),
		)
	}
}

layout_node_component :: proc(node: ^Node) {
	id := clay.ID("Node", node.handle.idx)
	node.clay_id = id

	border := clay.BorderElementConfig {
		width = {left = 2, right = 2, top = 2, bottom = 2},
		color = COLOR_NODE_BORDER,
	}
	background_color := COLOR_NODE_BACKGROUND

	if g.graph_selected_node == id {
		border.color = COLOR_NODE_BORDER_H
		background_color = COLOR_NODE_BACKGROUND_H
	} else {
		FIND_HIGHLIGHTS: {
			if g.graph_selected_node != {} {
				for highlighted in g.graph_highlighted_nodes {
					if highlighted == id {
						background_color = COLOR_NODE_BACKGROUND_H
						break FIND_HIGHLIGHTS
					}
					border.color = COLOR_NODE_BORDER_L
					background_color = COLOR_NODE_BACKGROUND_L
				}
			}
		}
	}

	if clay.UI()(
	{
		id = id,
		backgroundColor = background_color,
		floating = {
			clipTo = .AttachedParent,
			attachTo = .Parent,
			offset = g.graph_drawing_offset + node.position_px,
		},
		layout = {
			sizing = {
				width = {type = .Fixed, constraints = {sizeMinMax = {min = node.size_px.x}}},
				height = {type = .Fixed, constraints = {sizeMinMax = {min = node.size_px.y}}},
			},
		},
		border = border,
	},
	) {
		clay.TextDynamic(
			node.text,
			clay.TextConfig({textColor = BLACK, fontSize = 24, fontId = FONT_ID_TITLE_24}),
		)
	}
}

create_layout :: proc() -> clay.ClayArray(clay.RenderCommand) {
	clay.BeginLayout()
	// An example of laying out a UI with a fixed-width sidebar and flexible-width main content
	// NOTE: To create a scope for child components, the Odin API uses `if` with components that have children
	if clay.UI()(
	{
		id = clay.ID("OuterContainer"),
		layout = {
			sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
			padding = {16, 16, 16, 16},
			childGap = 16,
			layoutDirection = .TopToBottom,
		},
		backgroundColor = {250, 250, 255, 255},
	},
	) {
		if clay.UI()(
		{
			id = clay.ID("TopBar"),
			layout = {
				childGap = 16,
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(50)},
			},
			backgroundColor = COLOR_BACKGROUND,
		},
		) {
			if clay.UI()(
			{
				id = clay.ID("Name"),
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
					padding = {8, 8, 0, 0},
					childAlignment = {y = .Center},
				},
				backgroundColor = BURNT_SIENNA,
			},
			) {
				clay.Text(
					"WP Datapower | Zainteresowania | Styl i moda | Uroda | Pielegnacja i stylizacja paznokci",
					clay.TextConfig({textColor = BLACK, fontSize = 32, fontId = FONT_ID_TITLE_32}),
				)
			}

			if clay.UI()(
			{
				id = clay.ID("TopBarSpacing"),
				layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})}},
			},
			) {}
			button_component(clay.ID("Activate"), "Activate")
			button_component(clay.ID("SaveButton"), "Save")
			button_component(clay.ID("SaveAsButton"), "Save As")
			button_component(clay.ID("DetailsButton"), "Details")
			if clay.UI()(
			{
				id = clay.ID("TopBarSpacer"),
				layout = {
					sizing = {width = clay.SizingFixed(10), height = clay.SizingGrow({})},
					childAlignment = {y = .Center},
				},
			},
			) {
				clay.Text(
					"|",
					clay.TextConfig({textColor = BLACK, fontSize = 16, fontId = FONT_ID_TITLE_16}),
				)
			}
			button_component(clay.ID("DeleteButton"), "Delete")
		}
		if clay.UI()(
		{
			id = clay.ID("WorkflowEditor"),
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
				padding = {16, 16, 16, 16},
				childGap = 16,
			},
		},
		) {
			g.graph_editor_id = clay.ID("GraphEditor")
			if clay.UI()(
			{
				id = g.graph_editor_id,
				layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})}},
				clip = {horizontal = true, vertical = true},
				backgroundColor = COLOR_EDITOR_BACKGROUND,
			},
			) {
				if clay.UI()(
				{
					id = clay.ID("GraphEdges"),
					layout = {
						sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
					},
					// passing g.graph is not necessary, but this doesn't work when i pass
					custom = {customData = &g.graph},
				},
				) {}

				if g.graph.draw_nodes {
					node_iter := hm.make_iter(&g.graph.nodes)
					for node in hm.iter(&node_iter) {
						layout_node_component(node)
					}
				}
			}
			if clay.UI()(
			{
				id = clay.ID("Blocks"),
				layout = {
					layoutDirection = .TopToBottom,
					sizing = {width = clay.SizingFixed(300), height = clay.SizingGrow({})},
					padding = {16, 16, 16, 16},
					childGap = 16,
				},
				backgroundColor = COLOR_BACKGROUND,
			},
			) {
				if clay.UI()(
				{
					id = clay.ID("SearchBlock"),
					layout = {
						sizing = {width = clay.SizingGrow({})},
						padding = {16, 16, 16, 16},
						childGap = 16,
						childAlignment = {y = .Center},
					},
					backgroundColor = COLOR_BACKGROUND_L,
					cornerRadius = {6, 6, 6, 6},
				},
				) {
					clay.Text(
						"Search:",
						clay.TextConfig(
							{textColor = BLACK, fontSize = 24, fontId = FONT_ID_TITLE_24},
						),
					)
				}

				// Standard Odin code like loops, etc. work inside components.
				// Here we render 5 sidebar items.
				for bt in block_type {
					sidebar_item_component(bt)
				}
			}
		}
	}
	return clay.EndLayout()
}
