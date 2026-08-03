// The scream overlay: a borderless, transparent, non-activating panel that
// fades in near the corner of the screen and gets out of the way.
//
// Owning the window is the whole point — turbo can shake it directly, with
// none of the Accessibility permission that moving another app's window
// (the old Quick Look approach) required.
//
//   wilhelm-overlay --image face.png [--mode middle|turbo] [--seconds 2.5]

import Cocoa

// MARK: - args

var imagePath: String?
var mode = "middle"
var seconds = 2.4

var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--image": imagePath = args.next()
    case "--mode": mode = args.next() ?? mode
    case "--seconds": seconds = Double(args.next() ?? "") ?? seconds
    default: break
    }
}

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("wilhelm-overlay: \(message)\n".utf8))
    exit(1)
}

guard let imagePath else { die("missing --image") }
guard let image = NSImage(contentsOfFile: imagePath) else {
    die("could not load image at \(imagePath)")
}

// MARK: - click anywhere to dismiss

final class DismissView: NSView {
    override func mouseDown(with event: NSEvent) {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - window

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no dock icon, no menu bar takeover

let side: CGFloat = (mode == "turbo") ? 300 : 240
let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: side, height: side),
    // .nonactivatingPanel keeps keyboard focus where it was — the alert must
    // never steal the keystroke you were in the middle of typing.
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
panel.isMovableByWindowBackground = false

let container = DismissView(frame: NSRect(x: 0, y: 0, width: side, height: side))
container.wantsLayer = true
container.layer?.cornerRadius = 28
container.layer?.masksToBounds = true

let imageView = NSImageView(frame: container.bounds)
imageView.image = image
imageView.imageScaling = .scaleProportionallyUpOrDown
imageView.autoresizingMask = [.width, .height]
container.addSubview(imageView)
panel.contentView = container

// Bottom-right, clear of the Dock and menu bar.
var basePoint = NSPoint(x: 0, y: 0)
if let screen = NSScreen.main {
    let visible = screen.visibleFrame
    let margin: CGFloat = 28
    basePoint = NSPoint(x: visible.maxX - side - margin, y: visible.minY + margin)
    panel.setFrameOrigin(basePoint)
}

panel.alphaValue = 0
panel.orderFrontRegardless()
NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.11
    panel.animator().alphaValue = 1
}

// MARK: - turbo shake

if mode == "turbo" {
    let origin = basePoint
    let duration = 0.62
    let frameRate = 1.0 / 60.0
    var elapsed = 0.0

    Timer.scheduledTimer(withTimeInterval: frameRate, repeats: true) { timer in
        elapsed += frameRate
        guard elapsed < duration else {
            timer.invalidate()
            panel.setFrameOrigin(origin)
            panel.contentView?.layer?.setAffineTransform(.identity)
            return
        }

        // A driven oscillation, not random jitter: random offsets reads as a
        // glitch, while a fast sine that decays reads as something being
        // physically rattled. The axes use different frequencies so it never
        // collapses into a clean diagonal.
        let progress = elapsed / duration
        let decay = pow(1.0 - progress, 1.7)
        let amplitude = 34.0 * decay
        let dx = amplitude * sin(elapsed * 58.0)
        let dy = amplitude * 0.55 * sin(elapsed * 79.0 + 1.1)

        panel.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))

        // A slight counter-rotation sells the impact more than travel alone.
        let angle = CGFloat(0.035 * decay * sin(elapsed * 47.0))
        panel.contentView?.layer?.setAffineTransform(CGAffineTransform(rotationAngle: angle))
    }
}

// MARK: - auto dismiss

Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
    NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.16
        panel.animator().alphaValue = 0
    }, completionHandler: {
        app.terminate(nil)
    })
}

app.run()
