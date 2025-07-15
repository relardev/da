#+build !wasm32
#+build !wasm64p32

package game

import rl "vendor:raylib"
import "core:strings"

input_text_fill :: proc(){
	for {
		key := rl.GetCharPressed()
		if key <= 0 {
			break
		}
		_, err := strings.write_rune(&g.input_text, key)
		assert(err == nil, "Error writing rune to input text")
	}
}
