#+build wasm32, wasm64p32

package game

import "core:log"
import "core:strings"

input_text_fill :: proc() {
	for {
		key := js_get_key()
		if key <= 0 {
			break
		}
		log.info("Key pressed:", rune(key))
		_, err := strings.write_rune(&g.input_text, rune(key))
		assert(err == nil, "Error writing rune to input text")
	}
}

foreign _ {
	@(link_name = "js_get_key")
	js_get_key :: proc "c" () -> i32 ---
}
