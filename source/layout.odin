#+vet !unused-imports
package game

import clay "clay-odin"
// import "core:fmt"
import "core:log"
import "core:strings"
import textedit "core:text/edit"
import hm "handle_map"

COLOR_MODIFIER := clay.Color{20, 20, 20, 0}
WHITE := clay.Color{255, 255, 255, 255}
BLACK := clay.Color{0, 0, 0, 255}
GRAY := clay.Color{128, 128, 128, 255}

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

TOOLTIP_BACKGROUND := SAFFRON
TOOLTIP_BORDER := SAFFRON_H

COLOR_HIGHLIGHT_SEARCH := WHITE
COLOR_TEXT_SELECT := BURNT_SIENNA

layout_text :: proc(text: string, config: ^clay.TextElementConfig) {
	if len(g.search_query) > 0 && strings.contains(text, g.search_query) {
		if clay.UI()(
		{id = clay.ID("TextHighlightContainer", g.search_text_hilhglight_container_id)},
		) {
			g.search_text_hilhglight_container_id += 1
			text := text
			i := 0
			for {
				part := text[i:]
				idx := strings.index(part, g.search_query)
				if idx < 0 {
					if len(part) > 0 {
						clay.TextDynamic(part, config)
					}
					break
				}

				clay.TextDynamic(part[:idx], config)
				if clay.UI()(
				{
					id = clay.ID("TextHighlight", g.search_element_last_id),
					layout = {sizing = {width = clay.SizingFit({}), height = clay.SizingFit({})}},
					backgroundColor = COLOR_HIGHLIGHT_SEARCH,
				},
				) {
					g.search_element_last_id += 1
					clay.TextDynamic(g.search_query, config)
				}

				i += idx + len(g.search_query)
			}
		}
	} else {
		clay.TextDynamic(text, config)
	}
}

layout_node_core :: proc(node: ^Node) {
	if clay.UI()(
	{
		id = clay.ID("NodeCore", node.handle.idx),
		layout = {
			sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
			layoutDirection = .TopToBottom,
			padding = {16, 16, 16, 16},
			childGap = 16,
		},
	},
	) {
		if clay.UI()(
		{
			id = clay.ID("NodeTitle", node.handle.idx),
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFit({})},
				childAlignment = {x = .Center, y = .Center},
			},
		},
		) {
			layout_text(
				node.name,
				clay.TextConfig({textColor = BLACK, fontSize = 32, fontId = FONT_ID_TITLE_32}),
			)
		}
		layout_text(
			node.type,
			clay.TextConfig({textColor = BLACK, fontSize = 24, fontId = FONT_ID_TITLE_24}),
		)
		for argument in node.arguments {

			if clay.UI()(
			{
				id = argument.clay_id,
				layout = {sizing = {width = clay.SizingFit({}), height = clay.SizingFit({})}},
			},
			) {
				if len(argument.long_text) > 0 {
					point_over := clay.PointerOver(argument.clay_id)
					if point_over {
						data := clay.GetElementData(argument.clay_id)
						tooltip_id := clay.ID("tooltip")
						tooltip_data := clay.GetElementData(tooltip_id)
						if clay.UI()(
						{
							id = tooltip_id,
							layout = {
								padding = {8, 8, 8, 8},
								sizing = {
									width = clay.SizingFit({max = 300}),
									height = clay.SizingFit({}),
								},
							},
							floating = {
								offset = {
									data.boundingBox.width + 20,
									-tooltip_data.boundingBox.height / 2,
								},
								attachTo = .Parent,
								zIndex = 1,
							},
							backgroundColor = TOOLTIP_BACKGROUND,
							border = {
								width = {left = 2, right = 2, top = 2, bottom = 2},
								color = TOOLTIP_BORDER,
							},
						},
						) {
							clay.TextDynamic(
								argument.long_text,
								clay.TextConfig(
									{
										textColor = BLACK,
										fontSize = 16,
										fontId = FONT_ID_TITLE_16,
										wrapMode = .Words,
									},
								),
							)
						}
					}
				}
				layout_text(
					argument.text,
					clay.TextConfig({textColor = BLACK, fontSize = 16, fontId = FONT_ID_TITLE_16}),
				)
			}
		}
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
		floating = {clipTo = .AttachedParent, attachTo = .Parent, offset = node.position_px},
		layout = {
			sizing = {
				width = {type = .Fixed, constraints = {sizeMinMax = {min = node.size_px.x}}},
				height = {type = .Fixed, constraints = {sizeMinMax = {min = node.size_px.y}}},
			},
		},
		border = border,
	},
	) {
		layout_node_core(node)
	}
}

layout_ui_create :: proc() -> clay.ClayArray(clay.RenderCommand) {
	clay.SetCurrentContext(g.clay_ui_context)
	clay.BeginLayout()
	if clay.UI()(
	{
		id = clay.ID("OuterContainer"),
		layout = {
			sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
			padding = {16, 16, 16, 16},
			childGap = 16,
			layoutDirection = .TopToBottom,
		},
		backgroundColor = COLOR_BACKGROUND_L,
	},
	) {
		if clay.UI()(
		{
			id = clay.ID("TopBar"),
			layout = {
				childGap = 16,
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(50)},
			},
			cornerRadius = {topLeft = 8, topRight = 8, bottomLeft = 0, bottomRight = 0},
			backgroundColor = COLOR_BACKGROUND,
		},
		) {
			if g.recipe.Name != "" || g.recipe.Type != "" {
				if clay.UI()(
				{
					id = clay.ID("RecipeType"),
					layout = {
						sizing = {width = clay.SizingFit({}), height = clay.SizingGrow({})},
						padding = {8, 8, 0, 0},
						childAlignment = {y = .Center},
					},
					cornerRadius = {topLeft = 8, topRight = 8, bottomLeft = 0, bottomRight = 0},
					backgroundColor = BURNT_SIENNA,
				},
				) {
					layout_text(
						g.recipe.Type,
						clay.TextConfig(
							{textColor = BLACK, fontSize = 32, fontId = FONT_ID_TITLE_32},
						),
					)
				}

				if clay.UI()(
				{
					id = clay.ID("RecipeName"),
					layout = {
						sizing = {width = clay.SizingFit({}), height = clay.SizingGrow({})},
						padding = {8, 8, 0, 0},
						childAlignment = {y = .Center},
					},
					cornerRadius = {topLeft = 8, topRight = 8, bottomLeft = 0, bottomRight = 0},
					backgroundColor = BURNT_SIENNA,
				},
				) {
					layout_text(
						g.recipe.Name,
						clay.TextConfig(
							{textColor = BLACK, fontSize = 32, fontId = FONT_ID_TITLE_32},
						),
					)
				}
			}

			if clay.UI()(
			{
				id = clay.ID("TopBarSpacing"),
				layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})}},
			},
			) {}
		}

		if g.search_query != "" || g.focus == .Search {
			layout_search()
		}

		if clay.UI()(
		{
			id = clay.ID("MainWorkspace"),
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
				layoutDirection = .LeftToRight,
				childGap = 16,
			},
		},
		) {
			if clay.UI()(
			{
				id = clay.ID("LeftPanel"),
				layout = {
					sizing = {width = clay.SizingFit({}), height = clay.SizingGrow({})},
					padding = {8, 8, 8, 8},
					layoutDirection = .TopToBottom,
				},
				backgroundColor = COLOR_BACKGROUND,
			},
			) {
				border := clay.BorderElementConfig {
					width = {left = 2, right = 2, top = 2, bottom = 2},
					color = COLOR_NODE_BORDER,
				}

				if g.hide_noops {
					border = {}
				}

				if clay.UI()(
				{
					id = clay.ID("ToggleNoopNodesButton"),
					layout = {
						sizing = {width = clay.SizingGrow({}), height = clay.SizingFit({})},
						padding = {8, 8, 0, 0},
						childAlignment = {y = .Center},
					},
					border = border,
					backgroundColor = clay.Hovered() ? COLOR_NODE_BACKGROUND_H : COLOR_NODE_BACKGROUND,
				},
				) {
					clay.OnHover(proc "c" (id: clay.ElementId, pd: clay.PointerData, _: rawptr) {
							context = g.on_hover_context
							if pd.state == .PressedThisFrame {
								g.needs_redraw = true
								toggle_noops()
							}
						}, nil)
					clay.Text(
						"Noops",
						clay.TextConfig(
							{textColor = BLACK, fontSize = 32, fontId = FONT_ID_TITLE_32},
						),
					)
				}

			}
			if clay.UI()(
			{
				id = clay.ID("GraphBackground"),
				layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})}},
				backgroundColor = COLOR_EDITOR_BACKGROUND,
			},
			) {
				g.graph_editor_id = clay.ID("GraphEditorOuter")
				graph_viewer_data := new(CustomRenderData, allocator = context.temp_allocator)
				graph_viewer_data.type = .graph_viewer
				graph_viewer_data.data = GraphViewerData{}
				if clay.UI()(
				{
					id = g.graph_editor_id,
					layout = {
						sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
					},
					custom = {customData = graph_viewer_data},
				},
				) {}
			}
		}
	}
	return clay.EndLayout()
}

layout_search :: proc() {
	if clay.UI()(
	{
		id = clay.ID("SearchBar"),
		layout = {
			childGap = 16,
			sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(50)},
		},
		cornerRadius = {topLeft = 8, topRight = 8, bottomLeft = 0, bottomRight = 0},
		backgroundColor = COLOR_BACKGROUND,
	},
	) {
		font_id: u16 = FONT_ID_TITLE_32
		border := clay.BorderElementConfig {
			width = {left = 2, right = 2, top = 2, bottom = 2},
			color = g.focus == .Search ? COLOR_NODE_BORDER_H : {},
		}

		search_textbox_id := clay.ID("SearchTextbox")

		if g.mouse_interacting_with_id == search_textbox_id && g.focus == .Search {
			current_position := update_text_selection(search_textbox_id, g.mouse_position)

			g.search_textbox_state.selection[0] = current_position
		}

		if clay.UI()(
		{
			id = clay.ID("SearchBox"),
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFit({})},
				padding = {8, 8, 8, 8},
				childAlignment = {y = .Center},
			},
			border = border,
		},
		) {
			clay.OnHover(proc "c" (id: clay.ElementId, pd: clay.PointerData, _: rawptr) {
					context = g.on_hover_context
					if pd.state == .PressedThisFrame {
						g.needs_redraw = true
						g.focus = .Search
					}
				}, nil)
			clay.Text(
				"Search: ",
				clay.TextConfig({textColor = GRAY, fontSize = 32, fontId = font_id}),
			)
			if clay.UI()(
			{
				id = search_textbox_id,
				layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(32)}},
			},
			) {
				clay.OnHover(proc "c" (id: clay.ElementId, pd: clay.PointerData, _: rawptr) {
						context = g.on_hover_context
						if pd.state == .PressedThisFrame {
							g.needs_redraw = true
							g.mouse_interacting_with_id = id

							current_position := update_text_selection(id, pd.position)
							g.search_textbox_state.selection = {current_position, current_position}
						}
					}, nil)
				if g.focus == .Search {
					search_text_config := clay.TextConfig(
						{textColor = BLACK, fontSize = 32, fontId = font_id},
					)
					lo, hi := textedit.sorted_selection(&g.search_textbox_state)
					if lo != hi {
						clay.TextDynamic(g.search_query[:lo], search_text_config)
						if clay.UI()(
						{id = clay.ID("SearchHighlight"), backgroundColor = COLOR_TEXT_SELECT},
						) {
							clay.TextDynamic(g.search_query[lo:hi], search_text_config)
						}
						clay.TextDynamic(g.search_query[hi:], search_text_config)
					} else {
						cursor_pos := lo
						if clay.UI()({id = clay.ID("SearchBeforeCursor")}) {
							clay.TextDynamic(g.search_query[:cursor_pos], search_text_config)
						}
						clay.TextDynamic(g.search_query[cursor_pos:], search_text_config)
						// Cursor
						before_cursor_text_width := measure_text(
							g.search_query[:cursor_pos],
							font_id,
						)
						if clay.UI()(
						{
							id = clay.ID("SearchCursor"),
							layout = {
								sizing = {
									width = clay.SizingFixed(1),
									height = clay.SizingGrow({}),
								},
							},
							floating = {
								attachTo = .Parent,
								offset = {before_cursor_text_width, 0},
							},
							backgroundColor = COLOR_TEXT_SELECT,
						},
						) {}
					}
				} else {
					// search not focused, just draw text
					clay.TextDynamic(
						g.search_query,
						clay.TextConfig({textColor = BLACK, fontSize = 32, fontId = font_id}),
					)
				}
			}
		}
	}
}

layout_graph_create :: proc() -> clay.ClayArray(clay.RenderCommand) {
	clay.BeginLayout()

	if clay.UI()(
	{
		id = clay.ID("GraphEditor"),
		layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})}},
		clip = {horizontal = true, vertical = true},
	},
	) {
		edges_data := new(CustomRenderData, allocator = context.temp_allocator)
		edges_data.type = .edges
		edges_data.data = EdgesData{}
		if clay.UI()(
		{
			id = clay.ID("GraphEdges"),
			layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})}},
			custom = {customData = edges_data},
		},
		) {}

		if g.graph.draw_nodes {
			node_iter := hm.make_iter(&g.graph.nodes)
			for node in hm.iter(&node_iter) {
				layout_node_component(node)
			}
		}
	}
	return clay.EndLayout()
}


update_text_selection :: proc(id: clay.ElementId, mouse_position: Vec2) -> int {
	data := clay.GetElementData(id)
	offset_in_text := mouse_position.x - data.boundingBox.x
	half_codepoint_width := measure_text(" ", FONT_ID_TITLE_32) / 2

	new_selection := 0
	selection_updated := false
	for _, i in g.search_query {
		if measure_text(g.search_query[:i], FONT_ID_TITLE_32) + half_codepoint_width >=
		   offset_in_text {
			new_selection = i
			selection_updated = true
			break
		}
	}
	if !selection_updated {
		new_selection = len(g.search_query)
	}

	return new_selection
}
