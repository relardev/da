package game

import clay "clay-odin"
import "core:fmt"
import "core:math"
import "core:strings"
import hm "handle_map"
import rl "vendor:raylib"

clay_color_to_rl_color :: proc(color: clay.Color) -> rl.Color {
	return {u8(color.r), u8(color.g), u8(color.b), u8(color.a)}
}

clay_raylib_render :: proc(
	render_commands: ^clay.ClayArray(clay.RenderCommand),
	allocator := context.temp_allocator,
) {
	for i in 0 ..< render_commands.length {
		render_command := clay.RenderCommandArray_Get(render_commands, i)
		bounds := render_command.boundingBox

		switch render_command.commandType {
		case .None: // None
		case .Text:
			config := render_command.renderData.text

			text := string(config.stringContents.chars[:config.stringContents.length])

			// Raylib uses C strings instead of Odin strings, so we need to clone
			// Assume this will be freed elsewhere since we default to the temp allocator
			cstr_text := strings.clone_to_cstring(text, allocator)

			font := g.raylib_fonts[config.fontId].font
			rl.DrawTextEx(
				font,
				cstr_text,
				{bounds.x, bounds.y},
				f32(config.fontSize),
				f32(config.letterSpacing),
				clay_color_to_rl_color(config.textColor),
			)
		case .Image:
			config := render_command.renderData.image
			tint := config.backgroundColor
			if tint == 0 {
				tint = {255, 255, 255, 255}
			}

			imageTexture := (^rl.Texture2D)(config.imageData)
			rl.DrawTextureEx(
				imageTexture^,
				{bounds.x, bounds.y},
				0,
				bounds.width / f32(imageTexture.width),
				clay_color_to_rl_color(tint),
			)
		case .ScissorStart:
			rl.BeginScissorMode(
				i32(math.round(bounds.x)),
				i32(math.round(bounds.y)),
				i32(math.round(bounds.width)),
				i32(math.round(bounds.height)),
			)
		case .ScissorEnd:
			rl.EndScissorMode()
		case .Rectangle:
			config := render_command.renderData.rectangle
			if config.cornerRadius.topLeft > 0 {
				radius: f32 = (config.cornerRadius.topLeft * 2) / min(bounds.width, bounds.height)
				draw_rect_rounded(
					bounds.x,
					bounds.y,
					bounds.width,
					bounds.height,
					radius,
					config.backgroundColor,
				)
			} else {
				draw_rect(bounds.x, bounds.y, bounds.width, bounds.height, config.backgroundColor)
			}
		case .Border:
			config := render_command.renderData.border
			// Left border
			if config.width.left > 0 {
				draw_rect(
					bounds.x,
					bounds.y + config.cornerRadius.topLeft,
					f32(config.width.left),
					bounds.height - config.cornerRadius.topLeft - config.cornerRadius.bottomLeft,
					config.color,
				)
			}
			// Right border
			if config.width.right > 0 {
				draw_rect(
					bounds.x + bounds.width - f32(config.width.right),
					bounds.y + config.cornerRadius.topRight,
					f32(config.width.right),
					bounds.height - config.cornerRadius.topRight - config.cornerRadius.bottomRight,
					config.color,
				)
			}
			// Top border
			if config.width.top > 0 {
				draw_rect(
					bounds.x + config.cornerRadius.topLeft,
					bounds.y,
					bounds.width - config.cornerRadius.topLeft - config.cornerRadius.topRight,
					f32(config.width.top),
					config.color,
				)
			}
			// Bottom border
			if config.width.bottom > 0 {
				draw_rect(
					bounds.x + config.cornerRadius.bottomLeft,
					bounds.y + bounds.height - f32(config.width.bottom),
					bounds.width -
					config.cornerRadius.bottomLeft -
					config.cornerRadius.bottomRight,
					f32(config.width.bottom),
					config.color,
				)
			}

			// Rounded Borders
			if config.cornerRadius.topLeft > 0 {
				draw_arc(
					bounds.x + config.cornerRadius.topLeft,
					bounds.y + config.cornerRadius.topLeft,
					config.cornerRadius.topLeft - f32(config.width.top),
					config.cornerRadius.topLeft,
					180,
					270,
					config.color,
				)
			}
			if config.cornerRadius.topRight > 0 {
				draw_arc(
					bounds.x + bounds.width - config.cornerRadius.topRight,
					bounds.y + config.cornerRadius.topRight,
					config.cornerRadius.topRight - f32(config.width.top),
					config.cornerRadius.topRight,
					270,
					360,
					config.color,
				)
			}
			if config.cornerRadius.bottomLeft > 0 {
				draw_arc(
					bounds.x + config.cornerRadius.bottomLeft,
					bounds.y + bounds.height - config.cornerRadius.bottomLeft,
					config.cornerRadius.bottomLeft - f32(config.width.top),
					config.cornerRadius.bottomLeft,
					90,
					180,
					config.color,
				)
			}
			if config.cornerRadius.bottomRight > 0 {
				draw_arc(
					bounds.x + bounds.width - config.cornerRadius.bottomRight,
					bounds.y + bounds.height - config.cornerRadius.bottomRight,
					config.cornerRadius.bottomRight - f32(config.width.bottom),
					config.cornerRadius.bottomRight,
					0.1,
					90,
					config.color,
				)
			}
		case clay.RenderCommandType.Custom:
			canvas_start := Vec2{bounds.x, bounds.y} + g.graph_drawing_offset

			if g.graph.draw_gutters {
				for gutter in g.graph.gutters_vertical {
					rl.DrawText(
						fmt.ctprintf("%d", len(gutter.edges)),
						i32(canvas_start.x + gutter.pos + 5.0),
						i32(canvas_start.y + 5),
						20,
						rl.BLACK,
					)
					rl.DrawRectangleLinesEx(
						{
							x = canvas_start.x + gutter.pos,
							y = canvas_start.y,
							width = gutter.size_px,
							height = bounds.height,
						},
						2,
						rl.GREEN,
					)
				}

				for gutter in g.graph.gutters_horizontal {
					rl.DrawText(
						fmt.ctprintf("%d", len(gutter.edges)),
						i32(canvas_start.x + 5),
						i32(canvas_start.y + gutter.pos + 5.0),
						20,
						rl.BLACK,
					)
					rl.DrawRectangleLinesEx(
						{
							x = canvas_start.x,
							y = canvas_start.y + gutter.pos,
							width = bounds.width,
							height = gutter.size_px,
						},
						2,
						rl.BLUE,
					)
				}
			}

			edge_iter := hm.make_iter(&g.graph.edges)
			for edge in hm.iter(&edge_iter) {
				last := 0
				for point, i in edge.segments[1:] {
					if point == {} {
						break
					}
					start := edge.segments[i] + canvas_start
					end := point + canvas_start
					rl.DrawLineEx(start, end, 1, rl.RED)
					last = i
				}

				draw_arrow(edge.segments[last + 1] + canvas_start, edge.arrow_direction)
			}
		}
	}
}

draw_arrow :: proc(pos: Vec2, direction: i32) {
	// Draw an arrow at the given position, pointing in the specified direction
	// The arrow is drawn as a triangle with a base of 20 pixels and a height of 10 pixels
	arrow_base: f32 = 20.0
	arrow_height: f32 = 10.0

	upper_right, upper_left: Vec2
	switch direction {
	case down:
		upper_right = pos + {arrow_height, -arrow_base}
		upper_left = pos + {-arrow_height, -arrow_base}
	case left:
		upper_right = pos + {arrow_base, arrow_height}
		upper_left = pos + {arrow_base, -arrow_height}
	case right:
		upper_right = pos + {-arrow_base, -arrow_height}
		upper_left = pos + {-arrow_base, arrow_height}
	case:
		panic("Unsupported direction for arrow drawing")
	}

	// Draw the arrow triangle
	rl.DrawTriangle(pos, upper_right, upper_left, rl.RED)
}
// Helper procs, mainly for repeated conversions

@(private = "file")
draw_arc :: proc(
	x, y: f32,
	inner_rad, outer_rad: f32,
	start_angle, end_angle: f32,
	color: clay.Color,
) {
	rl.DrawRing(
		{math.round(x), math.round(y)},
		math.round(inner_rad),
		outer_rad,
		start_angle,
		end_angle,
		10,
		clay_color_to_rl_color(color),
	)
}

@(private = "file")
draw_rect :: proc(x, y, w, h: f32, color: clay.Color) {
	rl.DrawRectangle(
		i32(math.round(x)),
		i32(math.round(y)),
		i32(math.round(w)),
		i32(math.round(h)),
		clay_color_to_rl_color(color),
	)
}

@(private = "file")
draw_rect_rounded :: proc(x, y, w, h: f32, radius: f32, color: clay.Color) {
	rl.DrawRectangleRounded({x, y, w, h}, radius, 8, clay_color_to_rl_color(color))
}
