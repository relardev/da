package game

import clay "clay-odin"
// Define some colors.
COLOR_LIGHT :: clay.Color{224, 215, 210, 255}
COLOR_RED :: clay.Color{168, 66, 28, 255}
COLOR_ORANGE :: clay.Color{225, 138, 50, 255}
COLOR_BLACK :: clay.Color{0, 0, 0, 255}

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
		backgroundColor = COLOR_ORANGE,
	},
	) {
		clay.TextDynamic(
			label,
			clay.TextConfig({textColor = COLOR_BLACK, fontSize = 16, fontId = FONT_ID_TITLE_16}),
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
		backgroundColor = COLOR_ORANGE,
	},
	) {
		clay.Text(
			text,
			clay.TextConfig({textColor = COLOR_BLACK, fontSize = 16, fontId = FONT_ID_TITLE_16}),
		)
	}
}

layout_node_component :: proc(id: u32, offset: Vec2) {
	if clay.UI()(
	{
		id = clay.ID("Node", id),
		backgroundColor = COLOR_RED,
		floating = {
			clipTo = .AttachedParent,
			attachTo = .Parent,
			offset = g.graph_drawing_offset + offset,
		},
		layout = {
			sizing = {
				width = {type = .Fixed, constraints = {sizeMinMax = {min = 300}}},
				height = {type = .Fixed, constraints = {sizeMinMax = {min = 400}}},
			},
		},
	},
	) {
		clay.Text(
			"Node",
			clay.TextConfig({textColor = COLOR_BLACK, fontSize = 24, fontId = FONT_ID_TITLE_24}),
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
			backgroundColor = COLOR_LIGHT,
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
				backgroundColor = COLOR_RED,
			},
			) {
				clay.Text(
					"WP Datapower | Zainteresowania | Styl i moda | Uroda | Pielegnacja i stylizacja paznokci",
					clay.TextConfig(
						{textColor = COLOR_BLACK, fontSize = 32, fontId = FONT_ID_TITLE_32},
					),
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
					clay.TextConfig(
						{textColor = COLOR_BLACK, fontSize = 16, fontId = FONT_ID_TITLE_16},
					),
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
				backgroundColor = COLOR_LIGHT,
			},
			) {
				layout_node_component(0, {0, 0})
				layout_node_component(1, {500, 500})
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
				backgroundColor = COLOR_LIGHT,
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
					backgroundColor = COLOR_RED,
					cornerRadius = {6, 6, 6, 6},
				},
				) {
					clay.Text(
						"Search:",
						clay.TextConfig(
							{textColor = COLOR_BLACK, fontSize = 24, fontId = FONT_ID_TITLE_24},
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
