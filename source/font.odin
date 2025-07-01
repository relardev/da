package game

import clay "clay-odin"
import rl "vendor:raylib"

FONT_ID_TITLE_16 :: 3
FONT_ID_TITLE_24 :: 0
FONT_ID_TITLE_32 :: 1
FONT_ID_TITLE_56 :: 2

Raylib_Font :: struct {
	fontId: u16,
	font:   rl.Font,
}


loadFont :: proc(fontId: u16, fontSize: u16, path: cstring) {
	assign_at(
		&g.raylib_fonts,
		fontId,
		Raylib_Font{font = rl.LoadFontEx(path, cast(i32)fontSize * 2, nil, 0), fontId = fontId},
	)
	rl.SetTextureFilter(g.raylib_fonts[fontId].font.texture, rl.TextureFilter.TRILINEAR)
}

measure_text :: proc "c" (
	text: clay.StringSlice,
	config: ^clay.TextElementConfig,
	userData: rawptr,
) -> clay.Dimensions {
	line_width: f32 = 0

	font := g.raylib_fonts[config.fontId].font

	for i in 0 ..< text.length {
		glyph_index := text.chars[i] - 32

		glyph := font.glyphs[glyph_index]

		if glyph.advanceX != 0 {
			line_width += f32(glyph.advanceX)
		} else {
			line_width += font.recs[glyph_index].width + f32(glyph.offsetX)
		}
	}

	return {width = line_width / 2, height = f32(config.fontSize)}
}
