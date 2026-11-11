URGENT, READ BEFORE DOWNLOADING: BEFORE EXTRACTING THE ZIP, RIGHT-CLICK IT, GO TO "PROPERTIES", "GENERAL" AND SEARCH FOR "UNBLOCK"! Otherwise, Windows doesn't let you download the .DLL and you get an error on startup.

By the way, check my other project that makes Flowery say whatever you type!

Roaring Knight Window Slicer

Instructions

1. Keep the WindowSlice folder together; it can live anywhere, like a homeless person
2. Double-click Start-WindowSlice.cmd
3. On first run, you can change a lot of stuff. Window Slice then stays in the notification area by the clock, and you can open these settings again in its context menu
4. Tap your shortcut to slice the active window. To slice many windows windows, tap the second shortcut until the selection overlay appears, drag a rectangle over them, then release the shortcut. Matching windows get red outlines while you select. Right-click to cancel.

This program uses Windows PowerShell 5.1, WinForms, and .NET Framework components already included with Windows 10. It doesn't need AutoHotkey or .NET SDK.

- With Keep Fragments Draggable on, you can right-click fragments to remove them, or drag your mouse near them to remove many at once with a selection area.
Safety and limits

Limits

- There's no reliable Windows API that can tell whether every app has unsaved work. The default confirmation reminds you to save first.
- The shortcut can target an application's warning or save pop-up as a window.
- The effect uses a screen capture of the visible window. Minimized, hidden, desktop, and taskbar windows are ignored. Captures larger than 16 million pixels are rejected.
- Live slicing changes the source window's native region and restores it when you choose Restore original window, remove its last detached piece, or exit Window Slice normally. Avoid force-closing Window Slice while any live slices are active; an abrupt termination may leave the source window clipped. Live slicing is intended for ordinary, non-elevated application windows.
- Live fragment refresh uses Windows Graphics Capture when Windows supports disabling its colored capture border, so it doesn't include overlapping windows or raise the source above them.
- Small windows are supported as long as at least 16 visible pixels remain in both width and height.

Also, secret feature! Hover over a fragment and press the arrow keys to rotate it like a 3D object!

For the afterimages, go to the other folder.
