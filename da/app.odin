package main

import "base:runtime"
import clay "clay-odin"
import "core:c"
import "vendor:raylib"

windowWidth: i32 = 1024
windowHeight: i32 = 768

animationLerpValue: f32 = -1.0

FONT_ID_TITLE_56 :: 0

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

	loadFont(FONT_ID_TITLE_56, 56, "assets/iosevka.ttf")
}

should_run :: proc() -> bool {
	return !raylib.WindowShouldClose()
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


// Define some colors.
COLOR_LIGHT :: clay.Color{224, 215, 210, 255}
COLOR_RED :: clay.Color{168, 66, 28, 255}
COLOR_ORANGE :: clay.Color{225, 138, 50, 255}
COLOR_BLACK :: clay.Color{0, 0, 0, 255}

// Layout config is just a struct that can be declared statically, or inline
sidebar_item_layout := clay.LayoutConfig {
	sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(50)},
}

// Re-useable components are just normal procs.
sidebar_item_component :: proc(index: u32) {
	if clay.UI()(
	{
		id = clay.ID("SidebarBlob", index),
		layout = sidebar_item_layout,
		backgroundColor = COLOR_ORANGE,
	},
	) {}
}

createLayout :: proc(lerpValue: f32) -> clay.ClayArray(clay.RenderCommand) {
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
		},
		backgroundColor = {250, 250, 255, 255},
	},
	) {
		if clay.UI()(
		{
			id = clay.ID("SideBar"),
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
				id = clay.ID("ProfilePictureOuter"),
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
				if clay.UI()(
				{
					id = clay.ID("ProfilePicture"),
					layout = {
						sizing = {width = clay.SizingFixed(60), height = clay.SizingFixed(60)},
					},
				},
				) {}

				clay.Text(
					"Clay - UI Library",
					clay.TextConfig(
						{textColor = COLOR_BLACK, fontSize = 52, fontId = FONT_ID_TITLE_56},
					),
				)
			}

			// Standard Odin code like loops, etc. work inside components.
			// Here we render 5 sidebar items.
			for i in u32(0) ..< 5 {
				sidebar_item_component(i)
			}
		}

		if clay.UI()(
		{
			id = clay.ID("MainContent"),
			layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})}},
			backgroundColor = COLOR_LIGHT,
		},
		) {}
	}
	return clay.EndLayout()
}
