// app_hotkeys.js - Configuration file for all application hotkeys
// This file defines which keys should be handled by the app and which should be passed to the browser

// Define unified hotkeys list - all these hotkeys will be handled by the app regardless of focus state
var appHotkeys = [
    // Navigation and UI control
    { key: 'ArrowLeft', ctrl: false, alt: false, shift: false },
    { key: 'ArrowRight', ctrl: false, alt: false, shift: false },
    { key: 'ArrowUp', ctrl: false, alt: false, shift: false },
    { key: 'ArrowDown', ctrl: false, alt: false, shift: false },
    { key: 'Escape', ctrl: false, alt: false, shift: false }, // Escape
    
    // App shortcuts
    { key: 'n', ctrl: false, alt: false, shift: false }, // N key - toggle noops
    { key: 'f', ctrl: true, alt: false, shift: false },  // Ctrl+F - toggle/close search
    { key: 'd', ctrl: false, alt: false, shift: false }, // D key - debug mode
    
    // Function keys
    { key: 'f1', ctrl: false, alt: false, shift: false }, // F1 - toggle debug display
    { key: 'f2', ctrl: false, alt: false, shift: false }, // F2 - toggle camera debug
    { key: 'f3', ctrl: false, alt: false, shift: false }, // F3 - toggle nodes
    { key: 'f4', ctrl: false, alt: false, shift: false }, // F4 - toggle gutters
    
    // Text editing keys
    { key: 'Backspace', ctrl: false, alt: false, shift: false },
    { key: 'Delete', ctrl: false, alt: false, shift: false },
    
    // Common text editing shortcuts
    { key: 'a', ctrl: true, alt: false, shift: false },  // Ctrl+A (select all)
    { key: 'c', ctrl: true, alt: false, shift: false },  // Ctrl+C (copy)
    { key: 'v', ctrl: true, alt: false, shift: false },  // Ctrl+V (paste)
    { key: 'x', ctrl: true, alt: false, shift: false },  // Ctrl+X (cut)
    { key: 'z', ctrl: true, alt: false, shift: false },  // Ctrl+Z (undo)
    { key: 'y', ctrl: true, alt: false, shift: false },  // Ctrl+Y (redo)
];

// Function to check if a key event matches any hotkey in the list
function matchesHotkey(e, hotkeyList) {
    if (!hotkeyList) return false;
    
    return hotkeyList.some(hotkey => 
        e.key.toLowerCase() === hotkey.key.toLowerCase() && 
        e.ctrlKey === hotkey.ctrl && 
        e.altKey === hotkey.alt && 
        e.shiftKey === hotkey.shift
    );
}

// Add a new hotkey to the list
function addHotkey(key, ctrl = false, alt = false, shift = false) {
    appHotkeys.push({ key, ctrl, alt, shift });
}