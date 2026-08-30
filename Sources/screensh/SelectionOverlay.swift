import AppKit
import CoreGraphics

private enum KeyboardKeyCodes {
    static let defaultShortcutKey: UInt16 = 19
    static let altShortcutKey: UInt16 = 20
    static let sKey: UInt16 = 1
    static let escape: UInt16 = 53
    static let space: UInt16 = 49
}

struct ShortcutConfiguration: Equatable, CustomStringConvertible {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    static let `default` = ShortcutConfiguration(
        keyCode: KeyboardKeyCodes.defaultShortcutKey,
        modifiers: [.command, .shift]
    )

    var description: String {
        var result: [String] = []

        if modifiers.contains(.command) { result.append("⌘") }
        if modifiers.contains(.option) { result.append("⌥") }
        if modifiers.contains(.control) { result.append("⌃") }
        if modifiers.contains(.shift) { result.append("⇧") }

        let keyName: String
        switch keyCode {
        case KeyboardKeyCodes.escape:
            keyName = "Esc"
        case KeyboardKeyCodes.space:
            keyName = "Space"
        case KeyboardKeyCodes.defaultShortcutKey:
            keyName = "2"
        case KeyboardKeyCodes.altShortcutKey:
            keyName = "3"
        case KeyboardKeyCodes.sKey:
            keyName = "S"
        default:
            keyName = "Key(\(keyCode))"
        }

        result.append(keyName)
        return result.joined()
    }

    func matches(_ event: NSEvent) -> Bool {
        let activeFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == keyCode && activeFlags == modifiers
    }
}

@MainActor
final class SelectionOverlay: NSObject {
    private let displayWindow: SelectionWindow

    init(screen: NSScreen, completion: @escaping (NSRect?, Bool) -> Void) {
        self.displayWindow = SelectionWindow(screen: screen, completion: completion)
        super.init()
    }

    func show() {
        displayWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        displayWindow.orderOut(nil)
    }

    func close() {
        guard !displayWindow.isMiniaturized else { return }
        displayWindow.orderOut(nil)
        displayWindow.close()
        displayWindow.contentView = nil
        displayWindow.delegate = nil
    }
}

@MainActor
private final class SelectionWindow: NSWindow {
    init(screen: NSScreen, completion: @escaping (NSRect?, Bool) -> Void) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        acceptsMouseMovedEvents = true

        let view = SelectionView(completion: completion)
        contentView = view
        setFrame(screen.frame, display: true)
        makeFirstResponder(view)
        makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class SelectionView: NSView {
    private let completion: (NSRect?, Bool) -> Void
    private var startPoint: NSPoint = .zero
    private var currentPoint: NSPoint = .zero

    init(completion: @escaping (NSRect?, Bool) -> Void) {
        self.completion = completion
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var selectionRect: NSRect {
        let minX = min(startPoint.x, currentPoint.x)
        let minY = min(startPoint.y, currentPoint.y)
        let maxX = max(startPoint.x, currentPoint.x)
        let maxY = max(startPoint.y, currentPoint.y)
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor(white: 0.0, alpha: 0.42).setFill()
        bounds.fill()

        let rect = selectionRect
        let context = NSGraphicsContext.current?.cgContext
        if let context {
            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
            context.restoreGState()
        }

        if rect.width > 0 && rect.height > 0 {
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: rect.insetBy(dx: 1.0, dy: 1.0))
            outline.lineWidth = 2.0
            outline.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let rect = selectionRect
        let normalized = (rect.width > 0 && rect.height > 0) ? rect : nil

        completion(normalized, false)
        
        window?.orderOut(nil)
        window?.close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyboardKeyCodes.escape {
            completion(nil, true)
            
            window?.orderOut(nil)
            window?.close()
            return
        }

        super.keyDown(with: event)
    }
}

enum ScreenshotCapture {
    static func captureRegion(on screen: NSScreen, rect: NSRect) -> NSImage? {
        let displayID = displayID(for: screen)
        return captureRegion(displayID: displayID, screenFrame: screen.frame, rect: rect, backingScaleFactor: screen.backingScaleFactor)
    }

    static func captureRegion(displayID: CGDirectDisplayID, screenFrame: NSRect, rect: NSRect, backingScaleFactor: CGFloat) -> NSImage? {
        let safeRect = rect.intersection(screenFrame)
        guard safeRect.width > 0, safeRect.height > 0 else { return nil }

        guard let displayImage = CGDisplayCreateImage(displayID) else { return nil }

        let localX = (safeRect.minX - screenFrame.minX) * backingScaleFactor
        let localY = (safeRect.minY - screenFrame.minY) * backingScaleFactor
        let width = safeRect.width * backingScaleFactor
        let height = safeRect.height * backingScaleFactor

        let displayHeight = CGFloat(displayImage.height)
        let pixelRect = CGRect(
            x: localX,
            y: max(0, displayHeight - (localY + height)),
            width: width,
            height: height
        )

        let displayBounds = CGRect(x: 0, y: 0, width: CGFloat(displayImage.width), height: displayHeight)
        guard let cropped = displayImage.cropping(to: displayBounds.intersection(pixelRect)) else { return nil }

        let imageRep = NSBitmapImageRep(cgImage: cropped)
        guard let pngData = imageRep.representation(using: .png, properties: [:]) else { return nil }
        return NSImage(data: pngData)
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(number.intValue)
        }
        return CGMainDisplayID()
    }
}
