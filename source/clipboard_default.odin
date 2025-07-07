#+build !wasm32
#+build !wasm64p32

package game
import "core:mem"
import rl "vendor:raylib"

recipe_arena_align :: 8 * align_of(rawptr)

clipboard_paste :: proc() {
	txt := rl.GetClipboardText()
	assert(len(txt) + 1 < len(g.pasted), "clipboard text too long")
	mem.copy(&g.pasted[0], rawptr(txt), len(txt) + 1)
	g.pasted_len = i32(len(txt)) + 1

	clipboard_after_paste()
}
