#+vet !unused-imports
package game

import "base:runtime"
import clay "clay-odin"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:strings"
import textedit "core:text/edit"
import hm "handle_map"
import rl "vendor:raylib"

debug_example := #load("../debug_example.json")

ZOOM_SPEED: f32 = 0.1
MIN_ZOOM: f32 = 0.1
MAX_ZOOM: f32 = 10

SEARCH_BUFFER_SIZE :: 256

Vec2 :: [2]f32
Vec2i :: [2]i32

Game_Memory :: struct {
	run:                                 bool,
	clay_ui_debug_mode:                  bool,
	clay_ui_memory:                      rawptr,
	clay_ui_arena:                       clay.Arena,
	clay_ui_context:                     ^clay.Context,
	clay_graph_debug_mode:               bool,
	clay_graph_memory:                   rawptr,
	clay_graph_arena:                    clay.Arena,
	clay_graph_context:                  ^clay.Context,
	clay_node_memory:                    rawptr,
	raylib_fonts:                        [dynamic]Raylib_Font,
	prev_mouse_pos:                      Vec2,
	graph:                               Graph,
	graph_selected_node:                 clay.ElementId,
	graph_highlighted_nodes:             []clay.ElementId,
	graph_highlighted_edges:             []EdgeHandle,
	graph_editor_id:                     clay.ElementId,
	pasted:                              [50 * mem.Kilobyte]u8,
	pasted_len:                          i32,
	recipe:                              ^Recipe,
	recipe_arena:                        mem.Dynamic_Arena,
	recipe_allocator:                    mem.Allocator,
	camera:                              rl.Camera2D,
	graph_offset:                        Vec2,
	hide_noops:                          bool,
	debug_show:                          bool,
	debug_observe:                       [dynamic]cstring,
	debug_draw_camera:                   bool,
	search_query:                        string,
	search_text_hilhglight_container_id: u32,
	search_element_last_id:              u32,
	search_buffer:                       [SEARCH_BUFFER_SIZE]u8,
	search_textbox_state:                textedit.State,
	input_text_buf:                      [1024]u8,
	input_text:                          strings.Builder,
	focus:                               Element,
	needs_redraw:                        bool,
	mouse_interacting_with_id:           clay.ElementId,
	mouse_position:                      Vec2,
	on_hover_context:                    runtime.Context,
}

Element :: enum {
	Nothing,
	Search,
}

g: ^Game_Memory

update :: proc() {
	g.debug_observe = make([dynamic]cstring, 0, 100, allocator = context.temp_allocator)
	// Process inputs
	{
		g.mouse_position = rl.GetMousePosition()

		is_ctrl_down :=
			rl.IsKeyDown(.LEFT_CONTROL) ||
			rl.IsKeyDown(.RIGHT_CONTROL) ||
			rl.IsKeyDown(.CAPS_LOCK) ||
			rl.IsKeyDown(.LEFT_SUPER) ||
			rl.IsKeyDown(.RIGHT_SUPER)

		is_shift_down := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

		backspaces := 0
		lefts := 0
		rights := 0
		deletes := 0
		INPUT_READING: for {
			key := rl.GetKeyPressed()
			if key == .KEY_NULL {
				break INPUT_READING
			}

			g.needs_redraw = true
			#partial switch key {
			case .BACKSPACE:
				backspaces += 1
			case .DELETE:
				deletes += 1
			case .LEFT:
				lefts += 1
			case .RIGHT:
				rights += 1
			}
		}

		strings.builder_reset(&g.input_text)
		input_text_fill()

		switch g.focus {
		case .Nothing:
			// if rl.IsKeyPressed(.ESCAPE) {
			// 	g.run = false
			// }

			if rl.IsKeyPressed(.V) && is_ctrl_down {
				g.needs_redraw = true
				clipboard_paste()
			}

			if rl.IsKeyPressed(.F8) {
				g.needs_redraw = true
				mem.copy(&g.pasted[0], raw_data(debug_example), len(debug_example))
				g.pasted_len = i32(len(debug_example))
				clipboard_after_paste()
			}

			if rl.IsKeyPressed(.N) {
				g.needs_redraw = true
				toggle_noops()
			}

			if rl.IsKeyPressed(.F) && is_ctrl_down {
				g.needs_redraw = true
				g.focus = .Search
			}
			if rl.IsKeyPressed(.D) {
				g.needs_redraw = true
				g.clay_ui_debug_mode = !g.clay_ui_debug_mode
				clay.SetDebugModeEnabled(g.clay_ui_debug_mode)
			}
		case .Search:
			if rl.IsKeyPressed(.ESCAPE) {
				g.needs_redraw = true
				g.focus = .Nothing
			}
			if rl.IsKeyPressed(.F) && is_ctrl_down {
				g.needs_redraw = true
				g.focus = .Nothing
			}
			if rl.IsKeyPressed(.A) && is_ctrl_down {
				g.needs_redraw = true
				g.search_textbox_state.selection = {len(g.search_query), 0}
			}
			if lefts > 0 || rights > 0 {
				move: textedit.Translation = lefts > 0 ? .Left : .Right
				number := lefts > 0 ? lefts : rights
				if is_shift_down {
					for _ in 0 ..< number {
						textedit.select_to(&g.search_textbox_state, move)
					}
				} else {
					for _ in 0 ..< number {
						textedit.move_to(&g.search_textbox_state, move)
					}
				}
			}


			if strings.builder_len(g.input_text) > 0 {
				textedit.input_text(&g.search_textbox_state, strings.to_string(g.input_text))
			}
			g.search_query = strings.to_string(g.search_textbox_state.builder^)

			if backspaces > 0 && len(g.search_query) > 0 {
				for _ in 0 ..< backspaces {
					textedit.delete_to(&g.search_textbox_state, .Left)
				}
			}
			if deletes > 0 && len(g.search_query) > 0 {
				for _ in 0 ..< deletes {
					textedit.delete_to(&g.search_textbox_state, .Right)
				}
			}
			g.search_query = strings.to_string(g.search_textbox_state.builder^)
		}
		if rl.IsKeyPressed(.F4) {
			g.needs_redraw = true
			g.graph.draw_gutters = !g.graph.draw_gutters
		}
		if rl.IsKeyPressed(.F3) {
			g.needs_redraw = true
			g.graph.draw_nodes = !g.graph.draw_nodes
		}

		if rl.IsKeyPressed(.F2) {
			g.needs_redraw = true
			g.debug_draw_camera = !g.debug_draw_camera
		}
		if g.debug_draw_camera {
			observe_debug(
				fmt.ctprintf(
					"Camera: [%.2f, %.2f], zoom: %.2f",
					g.camera.target.x,
					g.camera.target.y,
					g.camera.zoom,
				),
			)
		}

		if rl.IsKeyPressed(.F1) {
			g.needs_redraw = true
			g.debug_show = !g.debug_show
		}

		g.search_element_last_id = 0
		g.search_text_hilhglight_container_id = 0

		if g.mouse_interacting_with_id != {} && !rl.IsMouseButtonDown(.LEFT) {
			g.mouse_interacting_with_id = {}
		}
	}

	mouse_pos := g.mouse_position

	observe_debug(fmt.ctprintf("Mouse: [%.2f, %.2f]", mouse_pos.x, mouse_pos.y))
	g.graph_selected_node = {}
	clay.SetCurrentContext(g.clay_ui_context)
	clay.SetPointerState(mouse_pos, rl.IsMouseButtonDown(rl.MouseButton.LEFT))
	clay.SetLayoutDimensions({cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()})
	is_pointer_over_editor := clay.PointerOver(g.graph_editor_id)
	observe_debug(fmt.ctprintf("pointer over editor: %v", is_pointer_over_editor))
	if is_pointer_over_editor {
		// MOUSE IN GRAPH
		clay.SetCurrentContext(g.clay_graph_context)
		clay.SetLayoutDimensions({9999999, 9999999})
		// if rl.IsKeyPressed(.D) {
		// 	g.clay_graph_debug_mode = !g.clay_graph_debug_mode
		// 	clay.SetDebugModeEnabled(g.clay_graph_debug_mode)
		// }
		observe_debug(fmt.ctprintf("graph offset: %v", g.graph_offset))
		mouse_in_graph_editor := rl.GetScreenToWorld2D(
			mouse_pos - (g.graph_offset * g.camera.zoom),
			g.camera,
		)
		observe_debug(
			fmt.ctprintf(
				"Graph Mouse: [%.2f, %.2f]",
				mouse_in_graph_editor.x,
				mouse_in_graph_editor.y,
			),
		)
		clay.SetPointerState(mouse_in_graph_editor, rl.IsMouseButtonDown(rl.MouseButton.LEFT))

		// select, highlight nodes and edges
		{
			node_handle: NodeHandle
			node_iter := hm.make_iter(&g.graph.nodes)
			for node in hm.iter(&node_iter) {
				if clay.PointerOver(node.clay_id) {
					g.graph_selected_node = node.clay_id
					node_handle = node.handle
					break
				}
			}

			if g.graph_selected_node != {} {
				g.graph_highlighted_nodes = graph_clay_connected_nodes(
					&g.graph,
					node_handle,
					context.temp_allocator,
				)

				g.graph_highlighted_edges = graph_edges_of(
					&g.graph,
					node_handle,
					context.temp_allocator,
				)
			} else {
				g.graph_highlighted_nodes = nil
				g.graph_highlighted_edges = nil
			}
		}

		// Pan
		if rl.IsMouseButtonDown(.LEFT) {
			g.needs_redraw = true
			delta := g.prev_mouse_pos - mouse_pos
			g.camera.target += delta / g.camera.zoom
		}

		wheel := rl.GetMouseWheelMove()
		// Mouse Wheel stuff
		{
			if wheel != 0 {
				g.needs_redraw = true
				if rl.IsKeyDown(.LEFT_SHIFT) {
					clay.UpdateScrollContainers(false, rl.GetMouseWheelMoveV(), rl.GetFrameTime())
				} else {
					g.camera.zoom += wheel * ZOOM_SPEED
					g.camera.zoom = clamp(g.camera.zoom, MIN_ZOOM, MAX_ZOOM)

					new_mouse_world_pos := rl.GetScreenToWorld2D(
						mouse_pos - (g.graph_offset * g.camera.zoom),
						g.camera,
					)
					g.camera.target += mouse_in_graph_editor - new_mouse_world_pos
					observe_debug(
						fmt.ctprintf(
							"Zoom: %.2f, Mouse World Pos: [%.2f, %.2f], %.2f, %.2f",
							g.camera.zoom,
							new_mouse_world_pos.x,
							new_mouse_world_pos.y,
							mouse_in_graph_editor.x,
							mouse_in_graph_editor.y,
						),
					)
				}
			}

		}
	} else {
		// MOUSE IN UI
		clay.UpdateScrollContainers(false, rl.GetMouseWheelMoveV(), rl.GetFrameTime())
	}
	if g.prev_mouse_pos != mouse_pos {
		g.needs_redraw = true
		g.prev_mouse_pos = mouse_pos
	}
}

draw :: proc() {
	rl.BeginDrawing()
	if !g.needs_redraw {
		rl.EndDrawing()
		return
	}
	clay.SetCurrentContext(g.clay_ui_context)
	ui_render_commands: clay.ClayArray(clay.RenderCommand) = layout_ui_create()
	clay_raylib_render(&ui_render_commands)
	if g.debug_show {
		rl.DrawFPS(10, 10)
	}
	for msg, i in g.debug_observe {
		rl.DrawText(msg, 10, rl.GetScreenHeight() - 30 * i32(i + 1), 20, rl.WHITE)
	}
	rl.EndDrawing()
}

@(export)
game_update :: proc() {
	update()
	draw()
	g.needs_redraw = false

	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .MSAA_4X_HINT})
	rl.InitWindow(1024, 768, "Recipe Viewer")
	rl.SetTargetFPS(rl.GetMonitorRefreshRate(0))
	// rl.SetTargetFPS(10)
	rl.SetExitKey(nil)
}

errorHandler :: proc "c" (errorData: clay.ErrorData) {
	context = runtime.default_context()
	panic("Error handler")
}

@(export)
game_init :: proc() {
	clay_min_memory_size := clay.MinMemorySize()
	clay_ui_memory := make([^]u8, clay_min_memory_size)

	clay_graph_memory := make([^]u8, clay_min_memory_size)

	clay_node_memory := make([^]u8, clay_min_memory_size)

	g = new(Game_Memory)

	g^ = Game_Memory {
		run = true,
		clay_ui_memory = clay_ui_memory,
		clay_ui_arena = clay.CreateArenaWithCapacityAndMemory(
			uint(clay_min_memory_size),
			clay_ui_memory,
		),
		clay_graph_memory = clay_graph_memory,
		clay_graph_arena = clay.CreateArenaWithCapacityAndMemory(
			uint(clay_min_memory_size),
			clay_graph_memory,
		),
		clay_node_memory = clay_node_memory,
		raylib_fonts = make([dynamic]Raylib_Font, 10),
		graph = Graph{draw_nodes = true},
		on_hover_context = context,
	}

	mem.dynamic_arena_init(&g.recipe_arena, alignment = recipe_arena_align)
	g.recipe_allocator = mem.dynamic_arena_allocator(&g.recipe_arena)

	g.recipe = new(Recipe, allocator = g.recipe_allocator)
	g.camera = {
		zoom = 1,
	}

	loadFont(FONT_ID_TITLE_16, 16, "assets/iosevka.ttf")
	loadFont(FONT_ID_TITLE_24, 24, "assets/iosevka.ttf")
	loadFont(FONT_ID_TITLE_32, 32, "assets/iosevka.ttf")
	loadFont(FONT_ID_TITLE_56, 56, "assets/iosevka.ttf")

	builder := strings.builder_from_bytes(g.search_buffer[:])
	// non_zero_resize(&builder.buf, 256)
	g.search_textbox_state.builder = &builder

	g.input_text = strings.builder_from_bytes(g.input_text_buf[:])

	game_hot_reloaded(g)
}

@(export)
game_should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			return false
		}
	}

	return g.run
}

@(export)
game_shutdown :: proc() {
	free(g.clay_ui_memory)
	free(g.clay_graph_memory)
	free(g.clay_node_memory)
	delete(g.raylib_fonts)
	mem.dynamic_arena_destroy(&g.recipe_arena)
	free(g)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	g.needs_redraw = true

	g.clay_ui_context = clay.Initialize(
		g.clay_ui_arena,
		{cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()},
		{handler = errorHandler},
	)
	clay.SetMeasureTextFunction(measure_text_clay, nil)

	g.clay_graph_context = clay.Initialize(
		g.clay_graph_arena,
		{999999, 999999},
		{handler = errorHandler},
	)
	clay.SetMeasureTextFunction(measure_text_clay, nil)
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	g.needs_redraw = true
	rl.SetWindowSize(i32(w), i32(h))
}

// Helper function to check if text input is focused
is_text_input_focused :: proc() -> bool {
	return g.focus == .Search
}

observe_debug :: proc(msg: cstring) {
	if g.debug_show {
		append(&g.debug_observe, msg)
	}
}

toggle_noops :: proc() {
	g.hide_noops = !g.hide_noops
	recipe_create_from_pasted()
}
