#+build wasm32, wasm64p32
// Implementations of `read_entire_file` and `write_entire_file` using the libc
// stuff emscripten exposes. You can read the files that get bundled by
// `--preload-file assets` in `build_web` script.


package game

import "base:runtime"
import "core:c"

@(export)
paste_callback :: proc "c" (len: c.int) {
	context = runtime.default_context()
	g.pasted[len] = 0
}

foreign _ {
	@(link_name = "js_paste_from_clipboard")
	js_paste_from_clipboard :: proc "c" (ptr: ^u8) ---
}

clipboard_paste :: proc() {
	js_paste_from_clipboard(&g.pasted[0])
}
