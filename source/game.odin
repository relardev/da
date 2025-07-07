package game

import "base:runtime"
import clay "clay-odin"
import "core:mem"
import hm "handle_map"
import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 180

Vec2 :: [2]f32
Vec2i :: [2]i32

Game_Memory :: struct {
	run:                     bool,
	clay_ui_debug_mode:      bool,
	clay_ui_memory:          rawptr,
	clay_ui_arena:           clay.Arena,
	clay_ui_context:         ^clay.Context,
	clay_graph_memory:       rawptr,
	clay_graph_arena:        clay.Arena,
	clay_graph_context:      ^clay.Context,
	clay_node_memory:        rawptr,
	raylib_fonts:            [dynamic]Raylib_Font,
	prev_mouse_pos:          Vec2,
	graph:                   Graph,
	graph_selected_node:     clay.ElementId,
	graph_highlighted_nodes: []clay.ElementId,
	graph_highlighted_edges: []EdgeHandle,
	graph_drawing_offset:    Vec2,
	graph_editor_id:         clay.ElementId,
	pasted:                  [8 * mem.Kilobyte]u8,
	pasted_len:              i32,
	recipe:                  ^Recipe,
	recipe_arena:            mem.Dynamic_Arena,
	recipe_allocator:        mem.Allocator,
}

g: ^Game_Memory

update :: proc() {
	clay.SetCurrentContext(g.clay_graph_context)
	if rl.IsKeyPressed(.D) {
		g.clay_ui_debug_mode = !g.clay_ui_debug_mode
		clay.SetDebugModeEnabled(g.clay_ui_debug_mode)
	}

	if rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}

	if rl.IsKeyPressed(.F4) {
		g.graph.draw_gutters = !g.graph.draw_gutters
	}
	if rl.IsKeyPressed(.F3) {
		g.graph.draw_nodes = !g.graph.draw_nodes
	}

	mouse_pos := rl.GetMousePosition()
	if clay.PointerOver(g.graph_editor_id) && rl.IsMouseButtonDown(.LEFT) {
		delta := g.prev_mouse_pos - mouse_pos
		g.graph_drawing_offset -= delta
	}
	g.prev_mouse_pos = mouse_pos

	// select, highlight nodes and edges
	{
		node_handle: NodeHandle
		g.graph_selected_node = {}
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

	if rl.IsKeyPressed(.V) && rl.IsKeyDown(.LEFT_CONTROL) {
		clipboard_paste()
	}

	clay.SetCurrentContext(g.clay_ui_context)
	clay.SetPointerState(rl.GetMousePosition(), rl.IsMouseButtonDown(rl.MouseButton.LEFT))
	clay.UpdateScrollContainers(false, rl.GetMouseWheelMoveV(), rl.GetFrameTime())
	clay.SetLayoutDimensions({cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()})
	clay.SetCurrentContext(g.clay_graph_context)
	clay.SetPointerState(rl.GetMousePosition(), rl.IsMouseButtonDown(rl.MouseButton.LEFT))
	clay.UpdateScrollContainers(false, rl.GetMouseWheelMoveV(), rl.GetFrameTime())
	clay.SetLayoutDimensions({cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()})
}

draw :: proc() {
	clay.SetCurrentContext(g.clay_ui_context)
	ui_render_commands: clay.ClayArray(clay.RenderCommand) = layout_ui_create()
	rl.BeginDrawing()
	clay_raylib_render(&ui_render_commands)
	// rl.DrawFPS(10, 10)
	// rl.DrawText(cstring(&g.pasted[0]), 10, rl.GetScreenHeight() - 30, 20, rl.BLACK)
	rl.EndDrawing()
}

@(export)
game_update :: proc() {
	update()
	draw()

	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .MSAA_4X_HINT})
	rl.InitWindow(1024, 768, "Odin")
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
	}

	mem.dynamic_arena_init(&g.recipe_arena, alignment = recipe_arena_align)
	g.recipe_allocator = mem.dynamic_arena_allocator(&g.recipe_arena)

	g.recipe = new(Recipe, allocator = g.recipe_allocator)

	loadFont(FONT_ID_TITLE_16, 16, "assets/iosevka.ttf")
	loadFont(FONT_ID_TITLE_24, 24, "assets/iosevka.ttf")
	loadFont(FONT_ID_TITLE_32, 32, "assets/iosevka.ttf")
	loadFont(FONT_ID_TITLE_56, 56, "assets/iosevka.ttf")

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
	graph_close(&g.graph)
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

	g.clay_ui_context = clay.Initialize(
		g.clay_ui_arena,
		{cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()},
		{handler = errorHandler},
	)
	clay.SetMeasureTextFunction(measure_text, nil)

	g.clay_graph_context = clay.Initialize(
		g.clay_graph_arena,
		{cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()},
		{handler = errorHandler},
	)
	clay.SetMeasureTextFunction(measure_text, nil)
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
	rl.SetWindowSize(i32(w), i32(h))
}
