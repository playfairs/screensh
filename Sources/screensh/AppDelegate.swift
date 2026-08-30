import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var selectionOverlay: SelectionOverlay?
    private var globalKeyMonitor: Any?
    private var shortcutCaptureMonitor: Any?
    private var isWaitingForShortcut = false

    private let defaults = UserDefaults.standard

    private var storedShortcut: ShortcutConfiguration

    private(set) var currentShortcut: ShortcutConfiguration {
        get { storedShortcut }
        set {
            storedShortcut = newValue
            defaults.set(Int(storedShortcut.keyCode), forKey: "screensh.keyCode")
            defaults.set(Int(storedShortcut.modifiers.rawValue), forKey: "screensh.modifiers")
            if NSApplication.shared.isRunning {
                installGlobalShortcut()
            }
        }
    }

    private var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    override init() {
        let storedKeyCode = defaults.object(forKey: "screensh.keyCode") as? Int ?? 19
        let storedModifierMask = defaults.object(forKey: "screensh.modifiers") as? Int ?? Int(NSEvent.ModifierFlags([.command, .shift]).rawValue)
        let storedModifiers = NSEvent.ModifierFlags(rawValue: UInt(storedModifierMask))
        self.storedShortcut = ShortcutConfiguration(keyCode: UInt16(storedKeyCode), modifiers: storedModifiers)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        configureStatusBar()
        installGlobalShortcut()
    }

    @objc private func takeScreenshot() {
        beginSelection()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 220),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "screensh"
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self

            let view = SettingsView(
                currentShortcut: currentShortcut,
                isAccessibilityTrusted: accessibilityTrusted,
                beginCapture: { [weak self] in self?.beginShortcutCapture() },
                onShortcutSelected: { [weak self] shortcut in
                    self?.setShortcut(shortcut)
                }
            )
            window.contentView = NSHostingView(rootView: view)
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if settingsWindow?.isVisible == false {
            settingsWindow = nil
        }
    }

    func setShortcut(_ shortcut: ShortcutConfiguration) {
        currentShortcut = shortcut
    }

    func beginShortcutCapture() {
        isWaitingForShortcut = true

        if let existing = shortcutCaptureMonitor {
            NSEvent.removeMonitor(existing)
            shortcutCaptureMonitor = nil
        }

        shortcutCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isWaitingForShortcut else {
                return event
            }

            if event.keyCode == 53 {
                self.isWaitingForShortcut = false
                self.shortcutCaptureMonitor = nil
                return nil
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            self.setShortcut(ShortcutConfiguration(keyCode: event.keyCode, modifiers: modifiers))
            self.isWaitingForShortcut = false
            self.shortcutCaptureMonitor = nil
            return nil
        }
    }

    private func configureStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "screensh")
        button.image?.isTemplate = true

        let menu = NSMenu(title: "screensh")
        let screenshotItem = NSMenuItem(title: "Take Screenshot", action: #selector(takeScreenshot), keyEquivalent: "")
        screenshotItem.keyEquivalentModifierMask = [.command, .shift]
        screenshotItem.keyEquivalent = "2"
        menu.addItem(screenshotItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit screensh", action: #selector(quitApplication), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func installGlobalShortcut() {
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }
            if self.currentShortcut.matches(event) {
                self.beginSelection()
            }
        }
    }

    private func beginSelection() {
        guard accessibilityTrusted else {
            let alert = NSAlert()
            alert.messageText = "Accessibility permission is required"
            alert.informativeText = "Please enable Accessibility access for screensh in System Settings > Privacy & Security > Accessibility."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        if let existing = selectionOverlay {
            existing.close()
            selectionOverlay = nil
        }

        let targetScreen = screenForPointer() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else { return }

        let overlay = SelectionOverlay(screen: screen) { [weak self] rect, cancelled in
            if let rect, !cancelled {
                self?.selectionOverlay?.hide()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let captureRect = rect
                    let screenFrame = screen.frame
                    let scale = screen.backingScaleFactor
                    let displayID = ScreenshotCapture.displayID(for: screen)

                    guard let image = ScreenshotCapture.captureRegion(displayID: displayID, screenFrame: screenFrame, rect: captureRect, backingScaleFactor: scale) else {
                        return
                    }

                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()

                    if let tiffRepresentation = image.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffRepresentation),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        pasteboard.setData(pngData, forType: .png)
                    }
                }
            }
            
            DispatchQueue.main.async {
                self?.selectionOverlay = nil
            }
        }

        selectionOverlay = overlay
        overlay.show()
    }

    private func screenForPointer() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    private func capture(_ rect: NSRect, on screen: NSScreen) {
        let displayID = ScreenshotCapture.displayID(for: screen)
        guard let image = ScreenshotCapture.captureRegion(displayID: displayID, screenFrame: screen.frame, rect: rect, backingScaleFactor: screen.backingScaleFactor) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let tiffRepresentation = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffRepresentation),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
        }
    }
}

struct SettingsView: View {
    let currentShortcut: ShortcutConfiguration
    let isAccessibilityTrusted: Bool
    let beginCapture: () -> Void
    let onShortcutSelected: (ShortcutConfiguration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard shortcut")
                .font(.headline)

            HStack {
                Text(currentShortcut.description)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                Spacer()
                Button("Capture new") {
                    beginCapture()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button("⌘⇧2 (default)") {
                    onShortcutSelected(ShortcutConfiguration(keyCode: 19, modifiers: [.command, .shift]))
                }
                Button("⌘⇧3") {
                    onShortcutSelected(ShortcutConfiguration(keyCode: 20, modifiers: [.command, .shift]))
                }
                Button("⌘⌥S") {
                    onShortcutSelected(ShortcutConfiguration(keyCode: 1, modifiers: [.command, .option]))
                }
            }

            if !isAccessibilityTrusted {
                Text("Enable Accessibility access in System Settings > Privacy & Security > Accessibility.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .frame(width: 330, height: 220)
    }
}
