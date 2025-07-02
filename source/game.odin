package game

import "base:runtime"
import clay "clay-odin"
import hm "handle_map"
import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 180

Vec2 :: [2]f32
Vec2i :: [2]i32

Game_Memory :: struct {
	run:                  bool,
	clay_debug_mode:      bool,
	clay_memory:          rawptr, // Pointer to the clay memory allocator.
	clay_arena:           clay.Arena, // Arena for clay memory allocations.
	raylib_fonts:         [dynamic]Raylib_Font,
	graph_drawing_offset: Vec2,
	graph_editor_id:      clay.ElementId,
	prev_mouse_pos:       Vec2,
	graph:                Graph,
}

g: ^Game_Memory

update :: proc() {
	if rl.IsKeyPressed(.D) {
		g.clay_debug_mode = !g.clay_debug_mode
		clay.SetDebugModeEnabled(g.clay_debug_mode)
	}

	if rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}

	mouse_pos := rl.GetMousePosition()
	if clay.PointerOver(g.graph_editor_id) && rl.IsMouseButtonDown(.LEFT) {
		delta := g.prev_mouse_pos - mouse_pos
		g.graph_drawing_offset -= delta
	}
	g.prev_mouse_pos = mouse_pos

	clay.SetPointerState(rl.GetMousePosition(), rl.IsMouseButtonDown(rl.MouseButton.LEFT))
	clay.UpdateScrollContainers(false, rl.GetMouseWheelMoveV(), rl.GetFrameTime())
	clay.SetLayoutDimensions({cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()})
}

draw :: proc() {
	render_commands: clay.ClayArray(clay.RenderCommand) = create_layout()
	rl.BeginDrawing()
	clay_raylib_render(&render_commands)
	rl.DrawFPS(10, 10)
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
	rl.SetTargetFPS(10)
	rl.SetExitKey(nil)
}

errorHandler :: proc "c" (errorData: clay.ErrorData) {
	context = runtime.default_context()
	panic("Error handler")
}

@(export)
game_init :: proc() {
	clay_min_memory_size := clay.MinMemorySize()
	clay_memory := make([^]u8, clay_min_memory_size)

	g = new(Game_Memory)

	g^ = Game_Memory {
		run          = true,
		clay_memory  = clay_memory,
		clay_arena   = clay.CreateArenaWithCapacityAndMemory(
			uint(clay_min_memory_size),
			clay_memory,
		),
		raylib_fonts = make([dynamic]Raylib_Font, 10),
	}

	hm.add(&g.graph.nodes, Node{text = "Node 54", position = {100, 100}})

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
	free(g.clay_memory)
	delete(g.raylib_fonts)
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

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.
	clay.Initialize(
		g.clay_arena,
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
