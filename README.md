# screensh
A fast and simple screenshot tool with instant clipboard copying and image uploading.

---
>[!IMPORTANT]
> For now, the app is SUPER minimal and only copies region capture, I'm trying to figure out
the best way to go about making this, I intend to make it similar to Flameshot or ShareX

### What it does
- Launches as a lightweight macOS menu-bar app.
- Registers a configurable global keyboard shortcut.
- Shows a fullscreen dimmed overlay on the active display.
- Lets the user drag a rectangle to select a region.
- Captures the exact selected area at display resolution.
- Encodes the result as PNG and copies it directly to the macOS pasteboard.
- Cancels cleanly with Escape and keeps the hotkey active for later captures.

### Requirements
- macOS 13+
- Xcode/Swift toolchain
- Accessibility permission for the global shortcut