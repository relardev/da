#!/usr/bin/env bash
set -eu

# This script cross-compiles the project from Linux to Windows (x86-64).
#
# Prerequisites (install once):
#   sudo apt-get install gcc-mingw-w64-x86-64 mingw-w64-x86-64-dev nasm wine
#
# It also needs a MinGW-compiled raylib. Download once:
#   curl -sL "https://github.com/raysan5/raylib/releases/download/5.5/raylib-5.5_win64_mingw-w64.zip" \
#     -o /tmp/raylib-mingw.zip && unzip -o /tmp/raylib-mingw.zip -d /tmp/raylib-mingw
#
# Usage:
#   ./build_windows.sh           # Release build (optimized)
#   ./build_windows.sh debug     # Debug build
#
# Testing:
#   wine build/windows/game_release.exe
#   wine build/windows/game_debug.exe

MODE="${1:-release}"
OUT_DIR="build/windows"

# MinGW-compiled raylib (not the MSVC one bundled with Odin).
# The Odin-bundled raylib.lib is compiled with MSVC and requires MSVC runtime
# symbols that aren't available in MinGW. We use the MinGW build instead.
RAYLIB_MINGW_LIB="/tmp/raylib-mingw/raylib-5.5_win64_mingw-w64/lib/libraylib.a"

if [ ! -f "$RAYLIB_MINGW_LIB" ]; then
    echo "MinGW raylib not found at $RAYLIB_MINGW_LIB"
    echo "Downloading raylib 5.5 for MinGW..."
    curl -sL "https://github.com/raysan5/raylib/releases/download/5.5/raylib-5.5_win64_mingw-w64.zip" \
        -o /tmp/raylib-mingw.zip
    mkdir -p /tmp/raylib-mingw
    unzip -o /tmp/raylib-mingw.zip -d /tmp/raylib-mingw
    echo "Downloaded successfully."
fi

# Clay library (MSVC-compiled, but has no CRT dependencies so it works with MinGW).
CLAY_LIB="source/clay-odin/windows/clay.lib"

mkdir -p "$OUT_DIR"

# --- Odin compile flags ---
case "$MODE" in
    debug)
        OBJ_PREFIX="game_debug"
        EXE_NAME="game_debug.exe"
        ODIN_FLAGS="-strict-style -vet -debug"
        ;;
    release)
        OBJ_PREFIX="game_release"
        EXE_NAME="game_release.exe"
        ODIN_FLAGS="-strict-style -vet -no-bounds-check -o:speed"
        ;;
    *)
        echo "Usage: $0 [debug|release]"
        exit 1
        ;;
esac

echo "=== Cross-compiling for Windows ($MODE) ==="

# --- Step 1: Compile to .obj files ---
echo "[1/4] Compiling Odin sources to Windows object files..."
rm -f "$OUT_DIR/$OBJ_PREFIX"*.obj
odin build source/main_release \
    -target:windows_amd64 \
    -build-mode:obj \
    -out:"$OUT_DIR/$OBJ_PREFIX.obj" \
    -use-single-module \
    $ODIN_FLAGS

# --- Step 2: Assemble Odin runtime support (Windows-specific) ---
# Odin's -build-mode:obj does not include the assembly file that provides
# __chkstk (stack probing) and _fltused (FP marker). We assemble a version
# derived from Odin's source. _tls_index is omitted because MinGW's CRT
# provides its own.
ODIN_RUNTIME_OBJ="$OUT_DIR/odin_runtime_procs.obj"
ODIN_RUNTIME_ASM="$OUT_DIR/odin_runtime_procs.asm"
echo "[2/4] Assembling Odin runtime support..."
cat > "$ODIN_RUNTIME_ASM" << 'NASM'
bits 64

global __chkstk
global _fltused

section .data
    _fltused:   dd 0x9875

section .text
; Stack probe routine required by MSVC/Odin calling convention.
; RAX = allocation size. Probes each page so the OS can map stack guard pages.
; From Odin base/runtime/procs_windows_amd64.asm
__chkstk:
    sub   rsp, 0x10
    mov   [rsp], r10
    mov   [rsp+0x8], r11
    lea   r10, [rsp+0x18]
    xor   r11, r11
    sub   r10, rax
    cmovb r10, r11
    mov   r11, gs:[0x10]
    cmp   r10, r11
    jnb   .end
    and   r10w, 0xf000
.loop:
    lea   r11, [r11-0x1000]
    mov   byte [r11], 0x0
    cmp   r10, r11
    jnz   .loop
.end:
    mov   r10, [rsp]
    mov   r11, [rsp+0x8]
    add   rsp, 0x10
    ret
NASM
nasm -f win64 "$ODIN_RUNTIME_ASM" -o "$ODIN_RUNTIME_OBJ"
rm -f "$ODIN_RUNTIME_ASM"

# --- Step 3: Link into .exe ---
echo "[3/4] Linking Windows executable..."

# Use MinGW GCC as the linker driver. It handles CRT startup (mainCRTStartup),
# TLS setup (_tls_index), and links against the correct MinGW runtime.
x86_64-w64-mingw32-gcc \
    "$OUT_DIR/$OBJ_PREFIX.obj" \
    "$ODIN_RUNTIME_OBJ" \
    "$RAYLIB_MINGW_LIB" \
    "$CLAY_LIB" \
    -lgdi32 -lwinmm -luser32 -lshell32 -lopengl32 \
    -mwindows \
    -o "$OUT_DIR/$EXE_NAME"

# --- Step 4: Copy assets ---
echo "[4/4] Copying assets..."
cp -R assets "$OUT_DIR/"

echo ""
echo "Windows $MODE build created: $OUT_DIR/$EXE_NAME"
echo "Test with: wine $OUT_DIR/$EXE_NAME"
