package da

import "base:runtime"
import clay "clay-odin"
import "core:c"
import "vendor:raylib"

windowWidth: i32 = 1024
windowHeight: i32 = 768

run: bool = true
animationLerpValue: f32 = -1.0

FONT_ID_TITLE_16 :: 3
FONT_ID_TITLE_24 :: 0
FONT_ID_TITLE_32 :: 1
FONT_ID_TITLE_56 :: 2

loadFont :: proc(fontId: u16, fontSize: u16, path: cstring) {
	assign_at(
		&raylib_fonts,
		fontId,
		Raylib_Font {
			font = raylib.LoadFontEx(path, cast(i32)fontSize * 2, nil, 0),
			fontId = fontId,
		},
	)
	raylib.SetTextureFilter(raylib_fonts[fontId].font.texture, raylib.TextureFilter.TRILINEAR)
}

errorHandler :: proc "c" (errorData: clay.ErrorData) {
	context = runtime.default_context()
	panic("Error handler")
}

init :: proc() {
	min_memory_size := clay.MinMemorySize()
	memory := make([^]u8, min_memory_size)
	arena: clay.Arena = clay.CreateArenaWithCapacityAndMemory(uint(min_memory_size), memory)
	clay.Initialize(
		arena,
		{cast(f32)raylib.GetScreenWidth(), cast(f32)raylib.GetScreenHeight()},
		{handler = errorHandler},
	)
	clay.SetMeasureTextFunction(measure_text, nil)
	raylib.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .MSAA_4X_HINT})
	raylib.InitWindow(windowWidth, windowHeight, "Raylib Odin Example")
	raylib.SetTargetFPS(raylib.GetMonitorRefreshRate(0))

	loadFont(FONT_ID_TITLE_16, 16, "assets/iosevka.ttf")
	loadFont(FONT_ID_TITLE_24, 24, "assets/iosevka.ttf")
	loadFont(FONT_ID_TITLE_32, 32, "assets/iosevka.ttf")
	loadFont(FONT_ID_TITLE_56, 56, "assets/iosevka.ttf")
}

should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if raylib.WindowShouldClose() {
			run = false
		}
	}

	return run
}


debugModeEnabled := false

update :: proc() {
	defer free_all(context.temp_allocator)

	animationLerpValue += raylib.GetFrameTime()
	if animationLerpValue > 1 {
		animationLerpValue = animationLerpValue - 2
	}
	windowWidth = raylib.GetScreenWidth()
	windowHeight = raylib.GetScreenHeight()
	if (raylib.IsKeyPressed(.D)) {
		debugModeEnabled = !debugModeEnabled
		clay.SetDebugModeEnabled(debugModeEnabled)
	}
	clay.SetPointerState(
		raylib.GetMousePosition(),
		raylib.IsMouseButtonDown(raylib.MouseButton.LEFT),
	)
	clay.UpdateScrollContainers(false, raylib.GetMouseWheelMoveV(), raylib.GetFrameTime())
	clay.SetLayoutDimensions({cast(f32)raylib.GetScreenWidth(), cast(f32)raylib.GetScreenHeight()})
	renderCommands: clay.ClayArray(clay.RenderCommand) = createLayout(
		animationLerpValue < 0 ? (animationLerpValue + 1) : (1 - animationLerpValue),
	)
	raylib.BeginDrawing()
	clay_raylib_render(&renderCommands)
	raylib.EndDrawing()
}

shutdown :: proc() {}

parent_window_size_changed :: proc(w, h: int) {
	raylib.SetWindowSize(c.int(w), c.int(h))
}
